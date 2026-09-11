extends CanvasLayer
class_name MapScreen
# The interactive run-graph map (DESIGN.md's field movement redesign:
# navigation redesign) - shows RunState's already-generated run_graph
# (see run_state.gd) as a real, clickable node layout instead of only
# the dev console printout.
#
# TWO MODES, one screen (step 3 - see each open_map_for_*() function's
# own comment for the full split):
# - open_map_for_viewing(): informational, dismissible, clicking a node
#   does nothing - "check the run's shape without committing to leave."
#   Reachable via a real HUD button (field_room.gd's MapButton) at any
#   time.
# - open_map_for_travel(): opened only by walking into a room's exit,
#   after a short scripted departure beat (field_room.gd's
#   _on_exit_entered() - see _spawn_exits()) - NOT dismissible without
#   picking a node (see _unhandled_input()),
#   and clicking a reachable node genuinely advances the run: RunState.
#   current_node moves, room_number increments, and the chosen node's
#   room loads for real.
#
# Same reusable-overlay shape as deck_viewer.gd (the established modal
# pattern this reuses rather than inventing a new one): a high-layer
# CanvasLayer, hidden by default, PROCESS_MODE_ALWAYS so it keeps working
# while the SceneTree is paused, a full-screen Backdrop blocking clicks
# to anything behind it, the whole tree paused while open (blocks field
# movement too - player.gd polls raw key state every physics frame,
# which no Control's mouse filter alone would stop). Reads RunState
# directly rather than being handed data, so any scene can add this as a
# plain child and just call one of the open functions - no wiring back
# to the caller needed, same as DeckViewer's open_deck().
#
# --- Layout direction: BOTTOM-TO-TOP (DECIDED for this step) ---
#
# Matches Slay the Spire's own map convention directly - the strongest
# reason to pick it here, since DESIGN.md's very first line names StS's
# core loop as this game's primary inspiration. "Climbing toward the
# boss" also fits Pillar 4's hard-but-fair, Souls-adjacent framing better
# than a left-to-right reading, which would read more like the FIELD
# ROOM's own side-scroll metaphor - a map is a different, more abstract
# kind of space than a room, and borrowing the room's own axis would
# blur that distinction rather than reinforce it. The opening node
# renders as its own bottom row, run_graph's layers climb upward above
# it, the boss node sits at the very top.

const NODE_HEIGHT := 90.0
const NODE_SPACING_X := 260.0
# +18.2% over the old 220 (2026-08-29, breathing-room pass) - crowding
# complaint was about both axes, not node size itself (label_width/
# icon_display_size untouched - see _node_width()'s own doc), so this
# only widens the GAP between node centers. Checked against the one hard
# constraint this pass came with: a 4-wide row (max_row_size, see _build_
# map()) must still fit scroll_container's width (1320px - Panel is
# 1400px wide, ScrollContainer takes offset_left=40/offset_right=-40 off
# that, see map_screen.tscn) without tripping its AUTO horizontal
# scrollbar. 4 * 260 = 1040px, comfortably under 1320 with ~280px to
# spare - no need to narrow _node_width() to make room.
const ROW_HEIGHT := 200.0
# +17.6% over the old 170 (2026-08-29, breathing-room pass) - same "gap
# only, not node size" reasoning as NODE_SPACING_X above (NODE_HEIGHT
# itself untouched). Only affects canvas_height/vertical scroll, which
# this pass's own horizontal-fit constraint doesn't apply to.
const ROW_MARGIN_TOP := 90.0
const ROW_MARGIN_BOTTOM := 90.0
# The canvas's own drawable size is computed from these plus however
# many rows/columns the current run's graph actually has (see
# _build_map()) - nothing here assumes a fixed layer_count or layer
# size, so retuning RunState's own graph-shape exports doesn't need a
# matching change here.
#
# Node WIDTH is no longer a fixed const alongside these (2026-08-28,
# texture-icon pass) - see _node_width()/_node_size() below, which
# derive it from icon_display_size + label_width + the icon/label
# margins, so a larger icon can't silently starve the label of room
# without anyone noticing (this pass's own investigation found exactly
# that: a flat 48px icon at the OLD fixed 170px width would have dropped
# the label budget from 114px to 92px, overflowing 4 of 14 place names).
# NODE_SPACING_X/ROW_HEIGHT/etc. stay fixed consts - only width tracks
# the icon now.

@export_group("Connections")
@export var dimmed_line_color: Color = Color(0.55, 0.55, 0.62, 0.4)
# Previous flat value (pre-2026-09-01 line-connection pass): Color(0.5,
# 0.5, 0.55, 0.16) - kept here, not deleted, as the reference point for
# how much brighter this pass raised it (alpha 0.16 -> 0.4, channels also
# nudged up slightly) while still reading as background context, not
# something worth tracing on its own - see the doc below for the
# contrast reasoning that hasn't changed, just the exact number.
@export var line_width: float = 3.0
@export var reachable_line_width: float = 5.0
# Change 1 (2026-08-29, edge-reachability pass) - edge appearance is a
# per-edge decision (see _edge_color()/_edge_width() below and _draw_
# connections()'s own call site): dimmed_line_color/line_width are what
# most edges in the graph get at any one time (every edge that doesn't
# leave the CURRENT node) - low contrast, present as background context
# rather than as information worth tracing. reachable_line_width (used
# with HudPalette.MAP_REACHABLE itself as the color - see _edge_color()'s
# own doc for why that's a direct read, not a mirrored export) is both
# brighter AND thicker for the small set of edges leaving the current
# node toward wherever it can actually go next.
#
# All three EXPORTED (2026-09-01, line-connection pass), not consts -
# HudPalette.MAP_REACHABLE itself deliberately stays a direct,
# un-mirrored read (per that pass's own explicit scope), so only the
# dimmed color and the two widths moved here.

@export var dot_radius: float = 4.0
# Edge-marker pass (2026-09-01, follow-up to the border-anchoring pass;
# REPLACES an open chevron this same doc used to describe - dots pass,
# same day) - a filled circle (canvas.draw_circle()) at each edge's
# DESTINATION anchor, centered exactly on it: the line reads as
# terminating in a point at the node border, not as a separate object
# sitting AT the border. No source-end marker - see _draw_connections()'s
# own call site, one draw_circle() call right after the line itself.
# Always uses the SAME color as the edge it belongs to (_edge_color(),
# already computed once per edge) rather than its own export, so a
# highlighted (green) edge's dot is automatically highlighted too, with
# nothing new to keep in sync. No direction vector needed (unlike the
# chevron it replaces), so _draw_connections() no longer computes one.

@export_range(0.0, 1.0, 0.01) var anchor_spread: float = 0.3
# REPLACES the even-spread fanning _fan_anchor() used to do (2026-09-01,
# direction-anchor pass) - an anchor's x-offset from its own node's center
# is now a fraction of how far HORIZONTALLY the edge's OTHER endpoint
# sits, not an index-in-fan position. See _direction_anchor() below for
# the exact formula. 0.3 is a starting point, not a measured value.

const MAP_BACKGROUND_COLOR := Color(0.13, 0.13, 0.16, 1)
# Matches Panel's own StyleBoxFlat_panel.bg_color in map_screen.tscn -
# duplicated on purpose, same "two files, one number, keep them in sync
# by hand" shape field_room.gd/room_state.gd's own EXIT_MARGIN pair
# already uses. A node "dimmed toward the background" has to blend
# toward the SAME color that's actually behind it (see _node_color()
# below), not a separately-eyeballed approximation of it.

@export_group("Node state colors")
@export_range(0.0, 1.0, 0.01) var visited_blend_amount: float = 0.9
@export_range(0.0, 1.0, 0.01) var unreachable_blend_amount: float = 0.15
# RAISED visited_blend_amount (0.78 -> 0.9) and LOWERED unreachable_
# blend_amount (0.45 -> 0.15) - 2026-08-28, widen-the-gap pass. Both
# still mean "how far to LERP toward MAP_BACKGROUND_COLOR," 0 = the full
# undimmed base hue, 1 = indistinguishable from the background - but
# retuning alone couldn't fix the real problem here (see _node_color()'s
# own doc): UNREACHABLE now blends a genuinely different, lighter base
# color (HudPalette.MAP_UNREACHABLE) instead of TROUGH, which is what
# actually creates the gap - the amount retune here is secondary, just
# pushing VISITED further into "barely there" and pulling UNREACHABLE's
# own blend down so its new brighter base isn't watered down much.
#
# The map's five conceptual node states as of this pass (a fifth,
# FORECLOSED, is planned but not built yet - see HudPalette.MAP_
# UNREACHABLE's own doc on the headroom reserved for it): CURRENT
# (HudPalette.MAP_CURRENT) and REACHABLE (HudPalette.MAP_REACHABLE) are
# the two "full weight" states, opaque, unchanged since the 2026-08-28
# legibility pass first moved them into HudPalette (biome-independent HUD
# chrome, same test SYSTEM_TEXT's own doc applies).
#
# VISITED/behind and UNREACHABLE/future are the two dimmed states, and as
# of THIS pass they finally derive from two DIFFERENT base colors, not
# one shared one: VISITED still blends HudPalette.TROUGH (this palette's
# designated recessive dark) toward MAP_BACKGROUND_COLOR - appropriate,
# since "the exact past" is supposed to nearly vanish. UNREACHABLE blends
# HudPalette.MAP_UNREACHABLE instead - a real design finding from the
# previous pass, not a preference: TROUGH (0.118, 0.110, 0.102) and MAP_
# BACKGROUND_COLOR (0.13, 0.13, 0.16) measure only ~0.06 apart in raw RGB
# distance, so EVERY color reachable by blending between them - which is
# ALL a shared-base VISITED/UNREACHABLE ever had - was confined to that
# same tiny near-black slice, regardless of blend_amount. No amount
# export could fix a base-color problem; MAP_UNREACHABLE fixes it by
# giving UNREACHABLE room to actually be a different color.
#
# "Visited" is still really "this node's layer is already behind the
# player," not a true per-room visited history - see _node_color()'s own
# doc, unchanged by this pass.
#
# Both blend amounts stay exported here, not on HudPalette itself, since
# "how much to blend" is this ONE consumer's own feel decision - see
# hud_palette.gd's own note on why TROUGH/MAP_UNREACHABLE don't carry
# their own baked-in blended variants.

@export_group("Node icon")
@export var icon_color_dark: Color = Color(0, 0, 0, 1)
@export var icon_color_light: Color = Color(1, 1, 1, 1)
# SPLIT by state (2026-08-28, icon-contrast fix), not one flat color - see
# _node_icon_color() below, same is_current/is_reachable split _node_text_
# color() already uses. ONLY read by _build_room_type_icon()'s PROCEDURAL
# fallback shapes (2026-08-28, texture-icon pass) - a real texture icon
# (ROOM_TYPE_ICONS below) is full-color art with its own fixed palette,
# never tinted; applying either of these to it would recolor the artwork
# unpredictably, not fix a contrast problem it doesn't have. Kept for the
# fallback specifically because a flat silhouette DOES have that problem -
# see this doc's own history for the measured numbers (DARK vs MAP_
# CURRENT/MAP_REACHABLE, LIGHT vs VISITED/UNREACHABLE, all clearing even
# text's 4.5:1 floor).
@export var icon_radius: float = 13.0
# ONLY the procedural fallback's own size now (2026-08-28, texture-icon
# pass) - a real texture icon uses icon_display_size below instead. Left
# at its old value/name rather than renamed, since it still means exactly
# what it always did for the shapes that still read it.
@export var icon_display_size: float = 48.0
# The rendered pixel size (both width and height - every source PNG in
# ROOM_TYPE_ICONS below is a perfect square, confirmed) a real texture
# icon scales to, via TextureRect below - one shared size, not a baked
# per-icon scale value, so retuning this rescales every room type
# uniformly regardless of its own source resolution (today: 1254x1254).
@export var label_width: float = 114.0
# The TARGET label budget _node_width() below solves for - not computed
# FROM the layout, the layout is computed to PRESERVE this. Exists as its
# own number (2026-08-28, texture-icon pass) specifically so a future
# icon_display_size retune can't silently shrink the label out from under
# the place names again: this pass's own investigation found that growing
# the OLD fixed-170px node to fit a 48px icon in place would have dropped
# the effective label budget from 114 to 92px, overflowing 4 of 14 place
# names ("Open Ground," "The Drainage," "Weighhouse," "The Lockers") -
# _node_width() below grows the NODE instead, keeping this exact budget
# fixed regardless of icon size.
@export var icon_left_margin: float = 6.0
@export var icon_text_gap: float = 8.0
@export var label_right_margin: float = 4.0
# icon_left_margin/label_right_margin no longer set a literal per-node
# inset (2026-09-08, block-centering pass - REPLACES this doc's own
# previous "fixed left margin + left-aligned label" scheme, and its
# reasoning for why THAT scheme's 12/8/10 values were tightened to
# 8/4/6): _add_node_button() now treats the icon and label as one block
# and CENTERS that block in the chip (see its own doc), so neither
# export controls a real position by itself any more - only their SUM
# (alongside icon_display_size/icon_text_gap/label_width) still matters,
# feeding _node_width() below. Kept as two separate exports anyway,
# rather than folded into one, purely so _node_width()'s own formula
# doesn't need restating - changing their split between each other has
# NO visible effect any more, only changing their total does.
#
# icon_text_gap is the one value from this trio that still means exactly
# what its name says: the fixed pixel gap between the icon and the label
# TEXT, held constant regardless of label length (that constancy is the
# actual point of centering the pair as a block, rather than centering
# each independently). RAISED 4 -> 8 in this same pass, back toward the
# pre-tightening original - 4 was tuned specifically to fake tightness
# against center-aligned text floating in a wide box, a problem that no
# longer exists once the block itself is what's centered; 8 reads as a
# more natural icon-to-label gap now that closing it doesn't fight
# anything else. icon_left_margin dropped 8 -> 6 and label_right_margin
# dropped 6 -> 4 to fully absorb that +4 elsewhere, so _node_width()'s
# own total is UNCHANGED by this pass - see its own doc for why that
# total specifically must not move.
#
# _node_width() (see below) computes the node's own total width as
# icon_left_margin + icon_display_size + icon_text_gap + label_width +
# label_right_margin - at these defaults: 6 + 48 + 8 + 114 + 4 = 180px,
# the exact same total the previous pass's own 8/4/6 produced. label_
# width itself is untouched here either - it's still the target budget
# the LONGEST place names need (see its own doc), not a margin, and
# every chip still sizes off this same fixed total regardless of label
# content - see _node_width()'s own doc for why width is no longer a
# flat const.

@export_group("Typography")
@export var room_name_font: Font = preload("res://assets/fonts/Spectral-Regular.ttf")
# The two-register split (2026-08-28, typography pass): a room's own
# identifying label - a real per-biome place name (RunNode.display_name,
# e.g. "The Yard") or, absent one, the plain room-TYPE word this file's
# own _type_name() returns as a fallback - is WORLD-VOICE content, same
# register card.gd's own name_font already establishes for a card's
# name (this is literally the same font file, Spectral-Regular.ttf, same
# "Regular = a name/label, not body flavor text" convention). Applied as
# a font override on the button itself, sitting alongside _node_text_
# color()'s own per-state color (full-color/full-contrast, untouched by
# this pass) - the FONT changed, not the color logic that was already
# carefully measured for contrast.
#
# The "(here)" annotation this doc used to describe is gone entirely
# (2026-09-06, map cleanup pass) - the current node is already
# distinguished by _node_color()'s own MAP_CURRENT background, so a
# second, redundant label calling it out added nothing but visual noise.
# Removed outright rather than left as dead machinery - see
# _add_node_button()'s own call site, which no longer calls anything
# after the icon.
@export var region_name_font_size: int = 18
# The region-name label's own size (2026-09-06, map cleanup pass,
# replacing the old "Choose Your Path"/"The Works" title) - deliberately
# far below the old title's 40px, and even a step below room_name_font's
# own inherited node-button size, since this is meant to read as
# secondary context in a corner, not a headline. See
# _setup_region_name_label() below for where this actually applies.

func _node_width() -> float:
	return icon_left_margin + icon_display_size + icon_text_gap + label_width + label_right_margin

func _node_size() -> Vector2:
	return Vector2(_node_width(), NODE_HEIGHT)

@export var reveal_layers_ahead: int = -1
# -1 (default, this step's actual behavior) = full visibility - every
# node in the graph is built and shown, matching item 2's "full
# visibility for now." A future value >= 0 would only reveal nodes
# within that many layers AHEAD of RunState.current_node's own layer -
# see _is_node_revealed() below, which _build_map() already calls
# before deciding whether to render a node (and, since a node with no
# rendered position also draws no connection lines to/from it - see
# _draw_connections()) at all. Flipping progressive reveal on later is
# purely changing this one number; no rendering code would need to
# change. What WOULD still need deciding at that point (deliberately not
# built now, since there's no config yet to justify it): whether a
# hidden node should just be absent (today's behavior for anything this
# function excludes) or show as a "?" fog-of-war placeholder instead -
# a content/feel decision, not a structural one this property already
# doesn't support.

@export var current_node_bottom_margin: float = 120.0
# How much breathing room to leave below the current node when auto-
# scrolling on open, rather than dead-centering it in the viewport - the
# player just came FROM here, so the view should be biased toward
# showing what's AHEAD (the rows climbing upward, toward the boss), not
# spend half the visible area on space below where they already are.

@export_group("Hover feedback")
@export var hover_scale: float = 1.08
@export var hover_scale_duration_sec: float = 0.12
@export var hover_border_color: Color = Color(1, 1, 1, 0.9)
@export var hover_border_width: float = 3.0
# Only ever applied to a button that's actually clickable right now (a
# reachable node, in travel mode - see _add_node_button()'s can_travel_
# here) - matches the existing UI language rather than inventing a new
# one: a border glow reuses StyleBoxFlat's own border properties (already
# how every node's flat-color background is built, just previously with
# border_width left at 0), and the scale-up reuses the same "grow
# slightly toward the cursor" idea card.gd's own hover animation already
# uses for cards in hand. Non-clickable nodes (current, unreachable, or
# ANY node in viewing mode - see open_map_for_viewing()'s own comment)
# get no hover response at all: the border-glow half is automatic
# (Godot's Button never shows its `hover` stylebox for a disabled
# button, regardless of actual mouse position - it shows `disabled`
# instead), and the scale-tween half is only ever WIRED (mouse_entered/
# mouse_exited connected) on a button that's already confirmed
# clickable in _add_node_button() - never connected at all for anything
# else, rather than connected-then-guarded.

@onready var backdrop: ColorRect = $Backdrop
@onready var region_name_label: Label = $Panel/RegionNameLabel
@onready var scroll_container: ScrollContainer = $Panel/ScrollContainer
@onready var canvas: Control = $Panel/ScrollContainer/Canvas
@onready var close_button: Button = $Panel/CloseButton

var _node_positions: Dictionary = {} # RunNode -> Vector2, the node's own drawn CENTER point in canvas-local space - read by _draw_connections().
var _travel_mode: bool = false
# false (viewing) is the safe default a freshly-instantiated MapScreen
# starts in - only open_map_for_travel() ever sets this true, and every
# room gets a brand new MapScreen instance on load (see field_room.tscn),
# so this never carries over stale from a previous room by accident.

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
	canvas.draw.connect(_draw_connections)
	_setup_region_name_label()

# Replaces the old "Choose Your Path"/"The Works" title (2026-09-06, map
# cleanup pass) - RunState.current_biome.biome_name (e.g. "The Sunken
# Works") is real per-run data, not an invented placeholder (see
# biome_data.gd's own biome_name doc: "matches DESIGN.md's Biomes section
# entry name exactly"). World-voice register (Spectral, same font a room's
# own name gets in _add_node_button() below) but sized and positioned
# (see RegionNameLabel's anchors in map_screen.tscn) to read as secondary
# context, not a heading.
#
# Plain white, no OverlayStyle outline (2026-09-07, label-contrast pass -
# REPLACES this doc's own previous HudPalette.WORLD_TEXT + light-outline
# treatment) - WORLD_TEXT is a dark ink meant for light grounds, needing
# OverlayStyle's outline as compensation only because this panel's own
# background (MAP_BACKGROUND_COLOR) is dark. White text needs no such
# compensation against that same dark background - the outline was pure
# unwanted glow once the base color was already legible on its own, not a
# convention worth keeping just because other world-voice labels use it
# (those sit over the variable, often-light field/battle art WORLD_TEXT
# was actually designed for - this panel never does). Called once, here,
# rather than from open_map_for_viewing()/open_map_for_travel() - the
# region name doesn't change between viewing and travel mode, so it
# doesn't need re-setting on every open.
func _setup_region_name_label() -> void:
	region_name_label.text = RunState.current_biome.biome_name
	region_name_label.add_theme_font_override("font", room_name_font)
	region_name_label.add_theme_font_size_override("font_size", region_name_font_size)
	region_name_label.add_theme_color_override("font_color", Color.WHITE)

# Escape closes the overlay - but ONLY in viewing mode. Travel mode is a
# real commitment to leave the room (the player already walked into the
# exit); backing out without picking a node isn't offered - see the
# class doc's own note on why, and open_map_for_travel()'s comment for
# where this got decided.
func _unhandled_input(event: InputEvent) -> void:
	if visible and not _travel_mode and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# Informational access, available any time via a real HUD button (see
# field_room.gd's MapButton) - not just a dev tool anymore (see the
# class doc). Reachable nodes are shown (still worth knowing "these are
# my options once I leave") but NOT clickable - see _add_node_button(),
# which only ever connects a node's press handler in travel mode.
# Dismissible normally: Close button or Escape both work.
func open_map_for_viewing() -> void:
	_travel_mode = false
	close_button.visible = true
	_build_map()
	visible = true
	get_tree().paused = true

# Opened only by walking into a room's exit - field_room.gd connects
# field_exit.gd's exit_entered signal to its own _on_exit_entered() (see
# _spawn_exits()), which plays a short scripted departure beat before
# calling this (2026-08-27, room-transition pass), rather than wiring
# exit_entered straight here. The player has already committed to leaving
# by the time this opens: no Close button, Escape
# does nothing while this is up (see _unhandled_input()) - a choice is
# required, not optional, per DESIGN.md's field movement redesign. Every
# reachable node is a real, clickable commitment now (see
# _on_node_pressed()) - picking one advances RunState for real and loads
# that room, it doesn't just re-render this screen in place the way an
# earlier pass of this step did.
func open_map_for_travel() -> void:
	_travel_mode = true
	close_button.visible = false
	_build_map()
	visible = true
	get_tree().paused = true

func close() -> void:
	visible = false
	get_tree().paused = false

# Tears down and rebuilds every node button from scratch - called once
# on open_map(), and again every time a click moves RunState.current_
# node (see _on_node_pressed()), so the current-position highlight and
# which nodes count as reachable always reflect the latest state rather
# than needing a second, separate "just update the highlighting" code
# path to stay in sync with the first.
func _build_map() -> void:
	for child in canvas.get_children():
		child.queue_free()
	_node_positions.clear()

	var rows := _rows()
	var max_row_size := 1
	for row in rows:
		max_row_size = maxi(max_row_size, row.size())

	# At least as wide as the visible panel area, so the graph centers
	# within the full panel (not just within a canvas tightly sized to
	# its own widest row, which is what used to leave it sitting left-of-
	# center with empty space on the right - the canvas never actually
	# FILLED the panel, so there was nothing for its own internal
	# centering to center WITHIN). Falls back to the content's own
	# natural width for the rare case a run's graph is wider than the
	# panel - see the "Layer sizes" export note on max_layer_size/
	# max_forward_edges for how wide that could realistically get.
	var content_width: float = max_row_size * NODE_SPACING_X
	var canvas_width: float = maxf(scroll_container.size.x, content_width)
	var canvas_height: float = (rows.size() - 1) * ROW_HEIGHT + ROW_MARGIN_TOP + ROW_MARGIN_BOTTOM
	canvas.custom_minimum_size = Vector2(canvas_width, canvas_height)

	# row_index 0 (the opening node) draws at the BOTTOM (largest Y - see
	# the class doc's "bottom-to-top" note); later rows climb upward.
	for row_index in rows.size():
		var row: Array = _ordered_row(rows, row_index)
		var y: float = canvas_height - ROW_MARGIN_BOTTOM - row_index * ROW_HEIGHT
		for i in row.size():
			var node: RunNode = row[i]
			if not _is_node_revealed(node):
				continue
			var x: float = canvas_width / 2.0 + (i - (row.size() - 1) / 2.0) * NODE_SPACING_X
			_add_node_button(node, Vector2(x, y))

	canvas.queue_redraw()
	# Re-center on the current node every time the map opens (not just
	# the first time this MapScreen instance is used) - the player should
	# always immediately see where they are and what's reachable without
	# scrolling manually, whether that's the first check of the run or
	# the fifth reopen in the same room.
	_retry_scroll_to_current_node()

# Setting scroll_container.scroll_vertical/horizontal goes straight to the
# ScrollContainer's own internal VScrollBar/HScrollBar, which clamps to
# ITS max_value - and that max_value only catches up to canvas's new
# custom_minimum_size (set above) on a later layout pass of its own, not
# synchronously with the assignment. Setting the target too early (even
# one call_deferred()'s worth of "later") silently clamps straight back
# to whatever the OLD, still-stale range allowed - confirmed empirically:
# opening the map right after a real scene transition (not immediately
# after this MapScreen node's own _ready(), the case a simpler one-shot
# deferred call happened to still work for) reproduced exactly this,
# landing on 0 instead of the intended target every time. Re-applying for
# a few frames, rather than guessing a single "safe" delay, is what
# actually survives that catch-up regardless of how many layout passes it
# takes on a given run.
func _retry_scroll_to_current_node() -> void:
	for i in 5:
		_scroll_to_current_node()
		await get_tree().process_frame

# Positions the SCROLL VIEWPORT on the current node - distinct from
# _build_map()'s own horizontal CONTENT centering (canvas_width above):
# that fixes where the graph sits within the canvas/panel; this fixes
# where the VIEW is looking within that (possibly taller- or wider-than-
# the-panel) canvas. Horizontally centered; vertically anchored near the
# BOTTOM of the viewport (see current_node_bottom_margin) rather than
# dead-centered, so opening the map reads as "here's what's ahead of
# you," not "here's you, with half the screen wasted below." Both axes
# clamped to the scrollable range so a node near an edge doesn't request
# a negative or past-the-end scroll position.
func _scroll_to_current_node() -> void:
	var pos: Variant = _node_positions.get(RunState.current_node)
	if pos == null:
		return
	var max_scroll_y := maxf(0.0, canvas.size.y - scroll_container.size.y)
	var max_scroll_x := maxf(0.0, canvas.size.x - scroll_container.size.x)
	var target_y: float = pos.y - scroll_container.size.y + current_node_bottom_margin
	scroll_container.scroll_vertical = int(clampf(target_y, 0.0, max_scroll_y))
	scroll_container.scroll_horizontal = int(clampf(pos.x - scroll_container.size.x / 2.0, 0.0, max_scroll_x))

# The opening node as its own row 0, then one row per RunState.run_graph
# layer, in order - the same "opening node isn't really part of run_
# graph" shape run_state.gd's own _print_run_graph() already handles by
# printing it separately first (see that function's comment for why:
# kept OUTSIDE the layered array on purpose, so generation logic never
# had to renumber anything to fit it in).
func _rows() -> Array:
	var rows: Array = [[RunState.opening_node]]
	for layer: RunLayer in RunState.run_graph:
		rows.append(layer.nodes)
	return rows

# Reorders a row's nodes for RENDERING only (2026-08-29, crossing-
# reduction pass) - never mutates the array `all_rows[row_index]` itself
# (that's the SAME array object as the corresponding RunLayer.nodes, not
# a copy - see _rows() above), which would silently reorder RunState.run_
# graph's own data as a side effect of drawing the map. Builds a fresh
# array instead, in sorted order, so the original is never touched -
# functionally the same guarantee a .duplicate()-then-sort would give,
# just without needing the extra intermediate copy.
#
# A single-pass barycenter heuristic (the standard technique for
# reducing edge crossings in a layered/Sugiyama-style graph drawing):
# each node is sorted by the average X already assigned to its own
# PARENTS - nodes in the row directly below it (all_rows[row_index - 1])
# whose .connections include this node. Safe to read that X straight
# from _node_positions because _build_map() processes rows in
# increasing row_index order (bottom row first - see its own "climb
# upward" doc), so every earlier row already has a final position by the
# time this runs. Ties keep the row's own original relative order
# (stable by construction: original_index is the tiebreaker, never
# random) - the common case for row_index 1, whose nodes ALWAYS share
# the single opening node as their only parent (run_graph[0] is always
# forced to size 1 - see run_state.gd's own _pick_layer_size() doc), so
# every node there would otherwise tie on the exact same barycenter.
#
# Deliberately ONE forward pass, never iterated to convergence and never
# looking at a node's own CHILDREN - this doesn't guarantee a crossing-
# free layout (that's NP-hard in general for graphs this shape), just a
# real reduction over "whatever order nodes happened to be created in,"
# which is what row_index's own raw array order was before this existed
# (see _build_map()'s own row-loop doc for how directly that fed x).
func _ordered_row(all_rows: Array, row_index: int) -> Array:
	var row: Array = all_rows[row_index]
	if row_index == 0:
		return row
	var previous_row: Array = all_rows[row_index - 1]
	var keyed: Array = []
	for i in row.size():
		var node: RunNode = row[i]
		var parent_xs: Array[float] = []
		for parent: RunNode in previous_row:
			if parent.connections.has(node) and _node_positions.has(parent):
				parent_xs.append(_node_positions[parent].x)
		# parent_xs empty only if a future change ever weakens _connect_
		# layers()'s own "every node gets at least one incoming edge from
		# the previous layer" guarantee (see that function's doc) without
		# this file being updated to match - falls back to the node's own
		# original index rather than crashing or dividing by zero, same
		# defensive spirit _is_node_revealed()'s callers already follow.
		var barycenter: float = i
		if not parent_xs.is_empty():
			var total := 0.0
			for x in parent_xs:
				total += x
			barycenter = total / parent_xs.size()
		keyed.append({"node": node, "key": barycenter, "original_index": i})
	keyed.sort_custom(func(a, b) -> bool:
		if a["key"] != b["key"]:
			return a["key"] < b["key"]
		return a["original_index"] < b["original_index"]
	)
	var ordered: Array = []
	for entry in keyed:
		ordered.append(entry["node"])
	return ordered

func _is_node_revealed(node: RunNode) -> bool:
	if reveal_layers_ahead < 0:
		return true
	return node.layer <= RunState.current_node.layer + reveal_layers_ahead

# The four node states this pass distinguishes. is_current/is_reachable
# are passed in rather than re-derived here since _add_node_button()'s
# caller already needs both for other reasons (can_travel_here, the
# "(here)" label) - no point computing either twice.
#
# ALWAYS fully opaque (2026-08-28, opacity-fix pass) - the original
# version of this dimmed visited/unreachable by lowering ALPHA, which
# let _draw_connections()'s own lines (drawn as part of canvas's own
# draw pass, BEFORE its child buttons draw on top - see that function's
# own doc) show straight through a dimmed node's semi-transparent
# background. Nodes are objects sitting ON TOP of the connection lines,
# not windows onto them - lerp()ing a base hue toward MAP_BACKGROUND_
# COLOR instead produces a faded LOOK while staying fully opaque, so a
# line ending at or passing behind a dimmed node is now genuinely
# covered, not just visually thinned out.
#
# VISITED and UNREACHABLE lerp two DIFFERENT base colors now (2026-08-28,
# widen-the-gap pass) - see visited_blend_amount/unreachable_blend_
# amount's own doc for the measured reason a single shared TROUGH base
# left the two indistinguishable, and HudPalette.MAP_UNREACHABLE's own
# doc for why its value was chosen to leave headroom for a planned fifth
# FORECLOSED state, not just to maximize contrast right now.
#
# "Visited" is really "this node's layer is already behind the player"
# (node.layer < RunState.current_node.layer), NOT a true per-room visited
# history - RunNode/RunState track no such thing (confirmed: neither
# RunNode nor RunState anywhere records which specific nodes the player
# has actually stood in, only current_node, the single "where am I now"
# pointer). Since the graph only ever advances exactly one layer at a
# time and never revisits an old one (see run_state.gd's own _connect_
# layers() doc), every node at an earlier layer is GENUINELY behind the
# player - but a sibling at that same earlier layer the player did NOT
# choose reads identically to one they actually walked through. That's a
# real, known gap, not silently smoothed over: if a true per-node visited
# distinction is ever wanted, RunNode needs an actual visited flag set at
# travel time (_on_node_pressed() below) - this pass doesn't add one,
# since "layer already passed" is what was asked for ("Visited/behind:
# dimmed, clearly past") and already reads correctly for that.
#
# current_node.layer works unmodified even when current_node IS the
# opening node (layer -1, see run_node.gd's own _init() doc) - nothing
# is ever behind the very first room, which is exactly what layer -1
# produces here without a special case.
func _node_color(node: RunNode, is_current: bool, is_reachable: bool) -> Color:
	if is_current:
		return HudPalette.MAP_CURRENT
	if is_reachable:
		return HudPalette.MAP_REACHABLE
	if node.layer < RunState.current_node.layer:
		return HudPalette.TROUGH.lerp(MAP_BACKGROUND_COLOR, visited_blend_amount)
	return HudPalette.MAP_UNREACHABLE.lerp(MAP_BACKGROUND_COLOR, unreachable_blend_amount)

# Dark text (HudPalette.TROUGH) on current/reachable, white on visited/
# unreachable (2026-08-28, text-contrast fix) - the two bright, saturated
# "full weight" backgrounds need dark text for contrast the same way the
# two dark, dimmed backgrounds need light text; one flat color across all
# four could never satisfy both pairs at once. TROUGH specifically, not a
# plain black or HudPalette.SYSTEM_TEXT - measured against BOTH bright
# backgrounds, TROUGH clears the 4.5:1 AA floor with real margin (~9.3:1
# on MAP_CURRENT, ~7.3:1 on MAP_REACHABLE); SYSTEM_TEXT was checked too
# and only just cleared MAP_REACHABLE (~4.6:1 - a hair above the floor,
# not the kind of margin text should ship with). White stays exactly as
# it was for visited/unreachable (~16:1 / ~6.6:1 - already comfortably
# passing, untouched here).
func _node_text_color(is_current: bool, is_reachable: bool) -> Color:
	if is_current or is_reachable:
		return HudPalette.TROUGH
	return Color.WHITE

# Same is_current/is_reachable split as _node_text_color() above, and for
# the same reason: current/reachable are the two bright, saturated
# backgrounds that need a DARK icon; visited/unreachable are the two dark
# backgrounds that need a LIGHT one. Uses icon_color_dark/icon_color_
# light rather than reusing _node_text_color()'s own HudPalette.TROUGH/
# Color.WHITE - kept as its OWN pair of exports (per this pass's own
# brief) so the icon's contrast can be retuned independently of the
# text's, even though both happen to land on black/white by measurement.
#
# Contrast report (WCAG relative luminance, against the 3:1 non-text/
# graphical floor - see this file's own investigation for why that's the
# right floor for a shape rather than text's stricter 4.5:1):
#   CURRENT     (icon_color_dark  vs MAP_CURRENT)  ~11.5:1 - clears 3:1 (and 4.5:1)
#   REACHABLE   (icon_color_dark  vs MAP_REACHABLE) ~9.0:1 - clears 3:1 (and 4.5:1)
#   VISITED     (icon_color_light vs VISITED bg)   ~16.1:1 - clears 3:1 (and 4.5:1)
#   UNREACHABLE (icon_color_light vs UNREACHABLE)   ~6.6:1 - clears 3:1 (and 4.5:1)
# All four clear even the stricter 4.5:1 text floor, not just the 3:1
# graphical one - splitting by state (rather than the old single flat
# icon_color) fully resolves the one real gap that constant color had
# (BLACK vs VISITED, ~1.3:1): VISITED now gets the LIGHT color instead of
# the dark one, the same swap that already fixed this exact background
# for text.
func _node_icon_color(is_current: bool, is_reachable: bool) -> Color:
	if is_current or is_reachable:
		return icon_color_dark
	return icon_color_light

func _add_node_button(node: RunNode, center: Vector2) -> void:
	var node_size := _node_size()
	var button := Button.new()
	button.custom_minimum_size = node_size
	button.position = center - node_size / 2.0
	button.focus_mode = Control.FOCUS_NONE
	button.text = _node_label(node)
	# World-voice: the room's own name (or, absent one, the plain type
	# fallback - see _node_label()'s own doc) is content about the WORLD,
	# same register a card's own name reads in (see room_name_font's own
	# doc for why this is literally the same font file).
	button.add_theme_font_override("font", room_name_font)
	# CENTER (Button's own default, left unset - 2026-09-08, block-
	# centering pass, REPLACES this doc's own previous HORIZONTAL_
	# ALIGNMENT_LEFT override): harmless either way once the content box
	# below is sized to the label's own measured text width, but CENTER
	# splits any sub-pixel measurement/render rounding evenly on both
	# sides instead of only ever trimming the right edge, which is the
	# safer default to leave in place.

	var is_current := node == RunState.current_node
	var is_reachable := RunState.current_node.connections.has(node)
	var bg_color := _node_color(node, is_current, is_reachable)
	# Explicit stylebox + font color overrides, not .modulate - modulate
	# tints a Button's text along with its background (multiplicatively),
	# which read fine for current/reachable's brighter colors but made
	# the dark visited/unreachable states' backgrounds pair with equally-
	# darkened text - unreadable, not just plain.
	#
	# NOT one flat color across all four states any more (2026-08-28,
	# text-contrast fix) - measured WCAG contrast against the ACTUAL
	# rendered background of each state showed flat white passing for
	# visited/unreachable (~16:1, ~6.6:1) but failing badly for current/
	# reachable (~1.8:1, ~2.3:1, against a 4.5:1 AA floor) - the two
	# brightest, most important states were also the two least legible,
	# exactly backwards. See _node_text_color() below for the fix and the
	# resulting numbers.
	var text_color := _node_text_color(is_current, is_reachable)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_disabled_color", text_color)
	# Only a reachable node, in TRAVEL mode, is ever actually clickable -
	# viewing mode shows the same reachable/unreachable colors (still
	# informative: "these are my options once I leave") but never wires
	# a press handler, so clicking never does anything there. The
	# current node is never clickable either way - it's where the player
	# already is.
	var can_travel_here := _travel_mode and is_reachable and not is_current
	button.disabled = not can_travel_here
	if can_travel_here:
		button.pressed.connect(_on_node_pressed.bind(node))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pivot_offset = node_size / 2.0 # scale grows from the button's own CENTER, not its top-left corner.
		button.mouse_entered.connect(_animate_hover.bind(button, hover_scale))
		button.mouse_exited.connect(_animate_hover.bind(button, 1.0))

	# Icon and label treated as ONE block, centered as a pair inside the
	# chip's fixed _node_width() (2026-09-08, block-centering pass -
	# REPLACES the previous fixed-left-margin icon + left-aligned label
	# this doc used to describe): a short label like "Forge" used to leave
	# the icon pinned to the chip's own left edge and every leftover pixel
	# stacked up on the right, reading as lopsided. Measuring the LABEL'S
	# OWN rendered text width (via room_name_font.get_string_size(),
	# rather than assuming the full label_width budget every node reserves
	# regardless of its actual name) gives this node's true block width -
	# icon_display_size + icon_text_gap + text_width - which centers
	# inside _node_width() below. That keeps the icon-to-label GAP fixed
	# at exactly icon_text_gap for every chip regardless of label length
	# (the actual ask this pass exists for), while the margins on either
	# side of the whole block come out equal for any label, long or
	# short. label_width itself is untouched - still the budget the
	# LONGEST place names need to fit (see its own doc); this only moves
	# where a SHORTER label's own block sits within a chip that stays the
	# same fixed width for every node either way.
	#
	# button.get_theme_font_size("font_size") resolves the project's
	# default Control font size (this button never overrides it - only
	# the FONT itself is overridden above) - measuring against any other
	# size would silently mismatch whatever size Button actually renders
	# the text at, undoing the whole point of measuring in the first place.
	var font_size := button.get_theme_font_size("font_size")
	var text_width := room_name_font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var block_width := icon_display_size + icon_text_gap + text_width
	var block_left := maxf(0.0, (node_size.x - block_width) / 2.0)
	var icon_x := block_left
	var label_left := block_left + icon_display_size + icon_text_gap
	# The content box's own width (node_size.x - label_left -
	# label_right_gap) comes out to EXACTLY text_width by construction -
	# button.alignment above is then free to be CENTER without changing
	# anything visible, since a box sized to its own text has nowhere left
	# to align text WITHIN it.
	var label_right_gap := maxf(0.0, node_size.x - label_left - text_width)

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(8)
	style.content_margin_left = label_left
	style.content_margin_right = label_right_gap
	# Same style for normal/disabled - a node that isn't clickable right
	# now doesn't need a hover-specific look, and this guarantees the
	# background never silently reverts to Godot's default Button theme
	# for whichever state wasn't explicitly covered.
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("disabled", style)

	# hover gets its own stylebox ONLY for a genuinely clickable node - a
	# bright border on top of the same background color, reusing
	# StyleBoxFlat's existing border properties rather than a second
	# visual mechanism. Godot already skips this stylebox entirely for a
	# disabled button (shows `disabled` instead, regardless of actual
	# mouse position), so a non-clickable node needs no extra guard here.
	# Carries the same content_margin as `style` above - a distinct
	# StyleBoxFlat instance means these aren't inherited automatically,
	# and without them the label would visibly jump left on hover.
	var hover_style := style
	if can_travel_here:
		hover_style = StyleBoxFlat.new()
		hover_style.bg_color = bg_color
		hover_style.set_corner_radius_all(8)
		hover_style.set_border_width_all(hover_border_width)
		hover_style.border_color = hover_border_color
		hover_style.content_margin_left = label_left
		hover_style.content_margin_right = label_right_gap
	button.add_theme_stylebox_override("hover", hover_style)

	_add_node_icon(button, node.room_type, _node_icon_color(is_current, is_reachable), icon_x)

	canvas.add_child(button)
	_node_positions[node] = center

# The icon lives in a plain Control anchored at icon_x (computed per node
# by the caller - see _add_node_button()'s own block-centering doc),
# vertically centered on the FULL button height - independent of the
# label's own content_margin-shifted text box. The icon's own box spans
# x=[icon_x, icon_x + icon_display_size], the label's text box starts at
# icon_x + icon_display_size + icon_text_gap - the two never share an
# x-range, so there's no overlap to check for per node, only
# once, structurally.
#
# mouse_filter = IGNORE is required, not cosmetic - without it this
# Control (sitting on top of part of the button's own clickable rect)
# would intercept clicks meant for the button underneath, silently
# breaking travel-mode clicks on any node whose icon happens to be under
# the cursor.
func _add_node_icon(button: Button, room_type: RoomType.Kind, color: Color, icon_x: float) -> void:
	var anchor := Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.position = Vector2(icon_x, NODE_HEIGHT / 2.0 - icon_display_size / 2.0)
	anchor.size = Vector2(icon_display_size, icon_display_size)
	_build_room_type_icon(anchor, room_type, color)
	button.add_child(anchor)

# The single source of truth for room-type -> icon texture (2026-08-28,
# texture-icon pass) - every preload() for these lives HERE, once, rather
# than scattered across call sites (map_screen.gd is the one file that
# needs to reach them - see _build_room_type_icon() below). Sourced from
# assets/icons/rooms/ (NOT assets/biomes/sunken_works/, which holds only
# the battle backdrop) - a flat const dict, not a resource, since this is
# a simple 1:1 lookup with no per-entry metadata beyond the texture
# itself. All seven RoomType.Kind values are covered as of this pass
# (2026-09-02, forge room-type-plumbing pass, added FORGE) - a missing
# entry is still handled explicitly, not assumed away - see _build_room_
# type_icon()'s own fallback below.
const ROOM_TYPE_ICONS := {
	RoomType.Kind.COMBAT: preload("res://assets/icons/rooms/Combat.png"),
	RoomType.Kind.TREASURE: preload("res://assets/icons/rooms/Treasure.png"),
	RoomType.Kind.EVENT: preload("res://assets/icons/rooms/Event.png"),
	RoomType.Kind.SHOP: preload("res://assets/icons/rooms/Shop.png"),
	RoomType.Kind.ELITE: preload("res://assets/icons/rooms/Elite.png"),
	RoomType.Kind.BOSS: preload("res://assets/icons/rooms/Boss.png"),
	RoomType.Kind.HEAP: preload("res://assets/icons/rooms/Heap.png"),
	RoomType.Kind.FORGE: preload("res://assets/icons/rooms/forge_icon.png"),
	# Lowercase/underscored filename (2026-09-02, forge room-type-plumbing
	# pass) - unlike the other six (Combat.png, Treasure.png, ...), which
	# this project's own art delivery already named PascalCase, this one
	# arrived as forge_icon.png; referenced as delivered rather than
	# renamed to match, same "asset as delivered, not renamed to fit a
	# convention" stance the belongings-sprite pass already took for
	# belonging_groundsheet_lighter.png.
}

# Real art (ROOM_TYPE_ICONS above) when this room type has an entry;
# otherwise a pushed warning plus the OLD procedural silhouette (see
# _build_fallback_room_type_icon() below) - never an empty node. Lives
# here, next to _type_name() (map_screen.gd's own enum-to-string
# mapping), rather than on RoomType itself - same per-consumer split
# _type_name()'s own doc already establishes: "how does a RoomType.Kind
# read as [something]" is this file's own concern, not the enum's.
#
# expand_mode = EXPAND_IGNORE_SIZE + stretch_mode = STRETCH_KEEP_ASPECT_
# CENTERED is what actually rescales the texture to fit anchor.size
# (icon_display_size) rather than rendering at the source PNG's own
# native resolution (1254x1254) or clamping to it as a minimum - a plain
# TextureRect defaults to sizing itself FROM the texture, exactly
# backwards from what a fixed display size needs.
#
# STRETCH_KEEP_ASPECT_CENTERED, not STRETCH_SCALE (2026-09-02, icon-
# aspect fix) - the original six room icons are all square (1254x1254),
# so blind STRETCH_SCALE into this slot's own square anchor.size never
# visibly distorted anything; FORGE's own source (forge_icon.png,
# originally 959x502) exposed the bug the first time a non-square icon
# ever reached this function - STRETCH_SCALE force-fills BOTH axes to
# anchor.size independently, stretching a non-square source out of its
# own proportions. This is the LOAD-BEARING fix for that (verified: it
# would have corrected the original 959x502 asset's own distortion too,
# not just the square-padded replacement that shipped alongside it in
# the same pass) - it makes this slot aspect-proof for every FUTURE icon
# regardless of that icon's own native proportions, not just this one
# asset. forge_icon.png was ALSO replaced with a square-padded (959x959)
# version in the same pass, matching the other six icons' own square
# convention - a good-practice pairing, not what actually fixes the bug;
# with only the stretch_mode change and the OLD 959x502 asset, the icon
# would render correctly proportioned but visibly smaller than its
# neighbors (only filling the axis the source's own aspect ratio allows),
# which is what the square-padded replacement additionally buys: reading
# at a consistent size against the other six, not just undistorted.
# texture_filter = LINEAR_WITH_MIPMAPS (not plain LINEAR) is
# the filter this pass's own brief specifically asked for: at a ~26x
# minification (1254px source down to 48px), linear alone still samples
# too small a neighborhood to avoid shimmer/aliasing on fine detail -
# mipmaps pre-average the texture at several resolutions so the sampler
# picks an already-downscaled level close to the target size instead.
# Requires the imported texture to actually HAVE mip levels baked in
# (mipmaps/generate=true in each PNG's own .import - NOT Godot's default
# for 2D art, see Coin_Icon.png/weapon icon .imports, which stay false on
# purpose for those) - set explicitly for these six on import, since the
# default would silently make this filter setting a no-op.
func _build_room_type_icon(anchor: Control, room_type: RoomType.Kind, color: Color) -> void:
	var texture: Texture2D = ROOM_TYPE_ICONS.get(room_type)
	if texture:
		var rect := TextureRect.new()
		rect.texture = texture
		# expand_mode MUST be set before .size below - a TextureRect's own
		# minimum size defaults to the TEXTURE's native resolution (here,
		# 1254x1254), and Control silently clamps any smaller .size back up
		# to that minimum until expand_mode says to ignore it. Setting size
		# first (as an earlier version of this did) looked correct in code
		# but got clamped straight back to 1254x1254 the instant it was
		# assigned - confirmed via this pass's own headless check, which
		# is exactly why this ordering is called out rather than assumed.
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.size = anchor.size
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		anchor.add_child(rect)
		return
	push_warning("No icon texture mapped for room type %s - falling back to the procedural marker." % RoomType.Kind.keys()[room_type])
	_build_fallback_room_type_icon(anchor, room_type, color)

# One flat Polygon2D silhouette per RoomType.Kind, sized off icon_radius -
# same "small hand-drawn shape, one exported color" placeholder language
# every other combat/status visual in this project already uses (status_
# badge.gd's own header), not a claim of final art direction (see
# DESIGN.md's Polish Backlog: ART DIRECTION SESSION). Kept intact as the
# explicit fallback for a room type with no ROOM_TYPE_ICONS entry (see
# _build_room_type_icon() above) - not dead code now that real art
# exists for every current type, since a future RoomType.Kind added
# without a matching icon lands here instead of an empty node. Every
# shape is built from points centered on local origin (0,0), then the
# Polygon2D's own `.position` is set to the anchor's center - the exact
# technique gold_display.gd's _build_coin() already uses for its own
# hand-drawn coin.
func _build_fallback_room_type_icon(anchor: Control, room_type: RoomType.Kind, color: Color) -> void:
	var center := anchor.size / 2.0
	var r := icon_radius
	match room_type:
		RoomType.Kind.COMBAT:
			# Crossed blades - two thin rectangles at +/-45 degrees.
			for angle in [PI / 4.0, -PI / 4.0]:
				var blade := Polygon2D.new()
				blade.polygon = _rect_points(r, r * 0.16)
				blade.position = center
				blade.rotation = angle
				blade.color = color
				anchor.add_child(blade)
		RoomType.Kind.TREASURE:
			# A gem - a hexagon with a point at the top, not a flat edge.
			var gem := Polygon2D.new()
			gem.polygon = _regular_polygon_points(r, 6, -PI / 2.0)
			gem.position = center
			gem.color = color
			anchor.add_child(gem)
		RoomType.Kind.EVENT:
			# An exclamation mark - a stem, then a separate small dot below it.
			var stem := Polygon2D.new()
			stem.polygon = _rect_points(r * 0.16, r * 0.55)
			stem.position = center + Vector2(0, -r * 0.25)
			stem.color = color
			anchor.add_child(stem)
			var dot := Polygon2D.new()
			dot.polygon = _regular_polygon_points(r * 0.18, 8)
			dot.position = center + Vector2(0, r * 0.75)
			dot.color = color
			anchor.add_child(dot)
		RoomType.Kind.SHOP:
			# A coin - same octagon-reads-as-circle shorthand gold_display.
			# gd's own coin already uses, one flat fill (no separate border
			# color here - that coin's two-tone look is ITS own material,
			# not a shape every circular icon needs to repeat).
			var coin := Polygon2D.new()
			coin.polygon = _regular_polygon_points(r, 8)
			coin.position = center
			coin.color = color
			anchor.add_child(coin)
		RoomType.Kind.ELITE:
			# A five-point star.
			var star := Polygon2D.new()
			star.polygon = _star_points(r, r * 0.45, 5)
			star.position = center
			star.color = color
			anchor.add_child(star)
		RoomType.Kind.BOSS:
			# A shield - flat top, tapering to a single point at the bottom.
			var shield := Polygon2D.new()
			shield.polygon = PackedVector2Array([
				Vector2(-r, -r * 0.6), Vector2(r, -r * 0.6),
				Vector2(r, r * 0.1), Vector2(0, r * 0.7), Vector2(-r, r * 0.1),
			])
			shield.position = center
			shield.color = color
			anchor.add_child(shield)
		RoomType.Kind.HEAP:
			# A small debris pile - the same flat-trapezoid-mound shape
			# field_heap.gd's own placeholder silhouette uses, scaled to
			# icon size, so the map icon and the field object read as the
			# same thing rather than two unrelated placeholders.
			var mound := Polygon2D.new()
			mound.polygon = PackedVector2Array([
				Vector2(-r, r * 0.6), Vector2(-r * 0.55, -r * 0.5),
				Vector2(r * 0.55, -r * 0.5), Vector2(r, r * 0.6),
			])
			mound.position = center
			mound.color = color
			anchor.add_child(mound)
		RoomType.Kind.FORGE:
			# A bench silhouette - a flat top bar over two short legs,
			# insurance only (2026-09-02, forge room-type-plumbing pass) -
			# ROOM_TYPE_ICONS above already covers FORGE with real art, so
			# this only ever renders if that texture fails to load. Echoes
			# field_forge.gd's own placeholder table shape (same "map icon
			# and field object read as the same thing" reasoning HEAP's own
			# mound above already established), deliberately no more
			# detailed than that placeholder itself - no anvil, no fire.
			var bench_top := Polygon2D.new()
			bench_top.polygon = _rect_points(r * 0.9, r * 0.14)
			bench_top.position = center + Vector2(0, -r * 0.25)
			bench_top.color = color
			anchor.add_child(bench_top)
			for leg_x in [-r * 0.55, r * 0.55]:
				var leg := Polygon2D.new()
				leg.polygon = _rect_points(r * 0.1, r * 0.45)
				leg.position = center + Vector2(leg_x, r * 0.25)
				leg.color = color
				anchor.add_child(leg)

func _rect_points(half_width: float, half_height: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half_width, -half_height), Vector2(half_width, -half_height),
		Vector2(half_width, half_height), Vector2(-half_width, half_height),
	])

# rotation_offset lets a shape start its first vertex somewhere other than
# due right (angle 0) - e.g. TREASURE's gem passes -PI/2 so a hexagon
# vertex points straight UP instead of two flat edges meeting at the top.
func _regular_polygon_points(radius: float, sides: int, rotation_offset: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in sides:
		var angle := rotation_offset + i * TAU / sides
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

# Alternates outer_radius/inner_radius around the circle to produce a
# star rather than a regular polygon - first point straight up (same
# "point up, not flat-top" read _regular_polygon_points()'s own
# rotation_offset gives TREASURE's gem, baked in here since every star
# this project draws wants the same orientation).
func _star_points(outer_radius: float, inner_radius: float, points_count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in points_count * 2:
		var radius := outer_radius if i % 2 == 0 else inner_radius
		var angle := -PI / 2.0 + i * PI / points_count
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _animate_hover(button: Button, target_scale: float) -> void:
	# Guards against overlapping tweens if the mouse enters/exits rapidly
	# (jittering right at the button's edge) - each button tracks its own
	# in-flight tween via metadata, since this one handler is shared
	# across every clickable node's mouse_entered/mouse_exited (bound
	# with which button and which target scale via .bind() above).
	if button.has_meta("hover_tween"):
		var existing: Tween = button.get_meta("hover_tween")
		existing.kill()
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, hover_scale_duration_sec)
	button.set_meta("hover_tween", tween)

# node.display_name if non-empty, else the plain room-type label
# (_type_name() below, now a thin wrapper around RoomType.display_name()
# - see its own doc). RunState no longer ever sets display_name
# (2026-08-31, label-unification pass removed its per-run naming pass -
# see run_state.gd's own _assign_room_types() doc), so EVERY node falls
# through to the type label today, opening_node included - the empty
# check still covers the opening node correctly (it's built outside
# run_graph and its display_name stays at RunNode's own "" default), it
# just no longer needs to distinguish it from any other node the way it
# did back when most nodes DID have a real per-biome name.
#
# Never appends a "(here)" annotation for the current node (2026-08-28,
# typography pass; that annotation itself was later removed outright,
# 2026-09-06 map cleanup pass) - this function just returns the room's
# own name/fallback, nothing else; the current node is distinguished
# purely by _node_color()'s own MAP_CURRENT background.
func _node_label(node: RunNode) -> String:
	return node.display_name if not node.display_name.is_empty() else _type_name(node.room_type)

# Thin wrapper around RoomType.display_name() (2026-08-31, label-
# unification pass - REPLACES this function's own former match statement,
# which was a third hand-copied name mapping independently drifting from
# run_hud.gd's HUD label and run_state.gd's dev console print - see
# RoomType.DISPLAY_NAMES's own doc). Kept as a named function rather than
# inlined at _node_label()'s own call site purely so this file doesn't
# need to change its one caller.
func _type_name(room_type: RoomType.Kind) -> String:
	return RoomType.display_name(room_type)

# Only ever connected in TRAVEL mode, on a button whose node was already
# confirmed reachable in _add_node_button() - no re-check needed here.
# Hides and unpauses BEFORE calling RoomState.load_room() on purpose:
# that call ends in SceneTransition.go_to(), which awaits its own fade
# Tweens - SceneTransition is a plain autoload CanvasLayer with no
# PROCESS_MODE_ALWAYS override, so its Tweens would themselves be frozen
# by this screen's own get_tree().paused = true if it were still in
# effect when go_to() starts, hanging the transition indefinitely
# instead of ever reaching the new room. Unpausing first avoids that
# entirely - verified headlessly that the full transition (including its
# two internal `await`s) actually completes rather than stalling.
func _on_node_pressed(node: RunNode) -> void:
	visible = false
	get_tree().paused = false
	RunLogger.log_room_entered(RunState.current_node, node)
	RunState.advance_to_next_room()
	RunState.current_node = node
	RoomState.load_room(node.room_type)

# Connected to canvas's own `draw` signal (see _ready()) rather than
# living in a second script on that node - canvas is a bare Control with
# no script of its own, and Godot allows drawing on any CanvasItem from
# a `draw`-signal handler during its own draw pass, not just from that
# node's own overridden _draw(). An edge whose target isn't in _node_
# positions (hidden by _is_node_revealed(), once progressive reveal is
# ever turned on) is simply skipped, not drawn to some fallback point.
#
# Anchored to node BORDERS, not centers (2026-09-01, line-connection
# pass - REPLACES this doc's own previous "node-center to node-center"
# claim): source anchor = TOP-center of the parent's rect, destination
# anchor = BOTTOM-center of the child's rect, via _direction_anchor()
# below - the two edges that actually FACE each other, given this map's own
# bottom-to-top row direction (row_index climbs to SMALLER y - see
# _build_map()'s own row loop), not the two edges facing away from each
# other. CORRECTED (2026-09-01, edge-marker pass, fixing a bug the
# anchoring pass itself introduced and shipped un-caught) - the original
# version of this doc/code used the parent's BOTTOM and the child's TOP
# instead, which are each node's FAR side relative to the other: with
# those, a line's true endpoints sat on the outside of both panels, so
# ~NODE_HEIGHT/2 of it at EACH end tunneled straight through that node's
# own opaque button (added as canvas's own CHILD, drawn after this pass -
# see _node_color()'s own doc on why nodes are opaque). Only the genuine
# gap in the middle was ever visible, which is why the LINE alone looked
# correct - the overshoot at both ends was invisible either way. The
# chevron this same pass added was NOT so lucky: drawn right at the true
# (far-side, buried) destination anchor with its wings pointing back
# INTO the child's own panel, it was 100% hidden - exactly the "I don't
# see the chevrons at all" symptom that caught this. No node rect is
# stored anywhere - _node_positions only ever holds each node's own
# CENTER (see that dict's own doc) - but every node shares the exact same
# size (_node_size(), derived from exported icon/label margins, never
# per-node), so the border offset from a stored center is always a fixed
# +/- NODE_HEIGHT/2.0, computed fresh at draw time rather than needing a
# second stored rect anywhere.
#
# DIRECTION-LEANED, not evenly fanned (2026-09-01, direction-anchor pass -
# REPLACES this doc's own previous "FANNED... spread across the middle
# 60%" claim, and the index-based _fan_anchor() it described): each
# anchor's x-offset from its own node's center now comes from _direction_
# anchor() below, a function of where the edge's OTHER endpoint actually
# sits, not this edge's position-in-fan. An edge whose two endpoints
# share an x anchors dead-center on BOTH ends (offset 0 either way), so
# it renders perfectly vertical; an edge to a node well off to one side
# leans its anchor toward that side. Only when two edges on the SAME
# border land close enough to collide (see _resolve_anchor_collisions()
# below) does anything get nudged off its own natural, direction-derived
# position - a lone edge, or two edges that don't actually overlap, are
# untouched regardless of how many total edges share that border.
#
# Incoming edges have no stored reverse pointer - RunNode.connections is
# forward-only, parent -> child (see run_node.gd's own doc) - and none is
# added there for this pass either, per its own explicit scope: `incoming`
# below is a plain local Dictionary (RunNode child -> Array[RunNode]
# parents, each value sorted by parent x) rebuilt fresh every draw call
# from every node's own forward `connections` - cheap enough at this
# graph's size (a handful of rows, a handful of nodes each) that a
# cached/incremental version isn't worth the complexity.
#
# Node panels still fully cover whatever's directly behind them (buttons
# are canvas's own CHILDREN, added after this draw pass runs each frame -
# see _node_color()'s own doc on why nodes are opaque specifically so a
# line ending under one is genuinely covered) - border anchoring just
# means a line's visible length no longer reaches under a panel in the
# first place, except at the anchor pixel itself.
#
# Each edge also gets a dot at its destination anchor (2026-09-01, edge-
# marker pass, follow-up to the border-anchoring pass above; chevron ->
# dot same day) - see dot_radius's own doc. Reuses the exact `color` this
# function already computed for the line itself, so a highlighted edge's
# dot matches automatically; no source-end counterpart.
#
# from_current (Change 1, 2026-08-29) is computed once per SOURCE node,
# not re-derived per edge - "this edge leads from the current node to
# one of its available next nodes" is exactly what node == RunState.
# current_node already means here, since node.connections (the thing
# this loop is about to iterate) IS the current node's own reachable
# set by construction (see _add_node_button()'s own is_reachable check,
# RunState.current_node.connections.has(node) - the same relationship,
# read from the other direction). No separate per-target reachability
# check needed.
func _draw_connections() -> void:
	var incoming: Dictionary = {} # RunNode (child) -> Array[RunNode] (parents with an edge into it), sorted by parent x.
	for row in _rows():
		for node: RunNode in row:
			if not _node_positions.has(node):
				continue
			for target in node.connections:
				if not _node_positions.has(target):
					continue
				if not incoming.has(target):
					incoming[target] = []
				incoming[target].append(node)
	for target in incoming:
		incoming[target].sort_custom(func(a, b) -> bool:
			return _node_positions[a].x < _node_positions[b].x
		)

	var min_gap := dot_radius * 2.0

	# Every target's own incoming anchors, direction-leaned then collision-
	# resolved as ONE group before any line is drawn (2026-09-01, direction-
	# anchor pass) - has to happen up front, separately from the source-side
	# loop below: edges arriving at the SAME target can originate from
	# different rows (different iterations of that loop), so a single edge
	# can't resolve collisions against dest-side siblings it hasn't been
	# computed alongside yet. Keyed by target, same order as incoming[target].
	var resolved_dest_anchors: Dictionary = {} # RunNode (child) -> Array[Vector2].
	for target in incoming:
		var target_center: Vector2 = _node_positions[target]
		var raw: Array[Vector2] = []
		for source in incoming[target]:
			raw.append(_direction_anchor(target_center, _node_positions[source], true))
		resolved_dest_anchors[target] = _resolve_anchor_collisions(raw, min_gap)

	for row in _rows():
		for node: RunNode in row:
			if not _node_positions.has(node):
				continue
			var from_current := node == RunState.current_node
			var outgoing: Array = []
			for target in node.connections:
				if _node_positions.has(target):
					outgoing.append(target)
			outgoing.sort_custom(func(a, b) -> bool:
				return _node_positions[a].x < _node_positions[b].x
			)
			# Source-side anchors are already grouped by construction (every
			# edge leaving THIS node, in one place) - no separate up-front
			# pass needed the way the dest side above requires.
			var node_center: Vector2 = _node_positions[node]
			var raw_source_anchors: Array[Vector2] = []
			for target in outgoing:
				# is_bottom=false: parent's TOP edge, facing the child above it.
				raw_source_anchors.append(_direction_anchor(node_center, _node_positions[target], false))
			var source_anchors := _resolve_anchor_collisions(raw_source_anchors, min_gap)
			for i in outgoing.size():
				var target: RunNode = outgoing[i]
				var source_anchor: Vector2 = source_anchors[i]
				var dest_siblings: Array = incoming[target]
				var dest_index := dest_siblings.find(node)
				var dest_anchor: Vector2 = resolved_dest_anchors[target][dest_index]
				var color := _edge_color(from_current)
				var width := _edge_width(from_current)
				canvas.draw_line(source_anchor, dest_anchor, color, width)
				canvas.draw_circle(dest_anchor, dot_radius, color)

# One anchor point along a node's bottom (is_bottom = true) or top
# (is_bottom = false) border, leaned toward wherever the edge's OTHER
# endpoint (`other_center`) actually sits (2026-09-01, direction-anchor
# pass - REPLACES the old index-in-fan _fan_anchor()): the raw horizontal
# displacement to `other_center`, clamped to +/- half the node's own width
# (so a far-off target can't drag the anchor past the node's own edge),
# scaled by anchor_spread. other_center.x == center.x (a shared column)
# yields offset 0 - dead center, same as a single untouched edge always
# looked - which is exactly what makes a same-column edge render vertical
# once BOTH its ends land on offset 0 this same way. Collisions between
# multiple anchors landing near each other on the same border are NOT
# handled here - see _resolve_anchor_collisions() below, applied by the
# caller across a whole border's worth of these at once.
func _direction_anchor(center: Vector2, other_center: Vector2, is_bottom: bool) -> Vector2:
	var max_off := _node_width() / 2.0
	var x_offset := clampf(other_center.x - center.x, -max_off, max_off) * anchor_spread
	var y := center.y + (NODE_HEIGHT / 2.0 if is_bottom else -NODE_HEIGHT / 2.0)
	return Vector2(center.x + x_offset, y)

# Nudges apart any anchors in `anchors` (all on the same border, same y,
# already in left-to-right order) that land within `min_gap` of their
# neighbor - a direction-leaned anchor has no built-in separation the way
# the old even-spread fan did, so two edges leaning toward the same side
# can genuinely land on top of each other (2026-09-01, direction-anchor
# pass). Walks left to right collecting maximal RUNS of mutually-close
# points (a "cluster") rather than pushing everything after the first
# collision further right - a point outside every cluster is returned
# completely unchanged, satisfying "don't disturb anchors that aren't
# colliding" even when an earlier, unrelated cluster exists on the same
# border. Each cluster is respaced EVENLY around its own original average
# x, exactly min_gap apart, left-to-right order preserved - the minimal,
# symmetric correction for that group specifically, not a directional
# shove. y is untouched throughout; only x moves.
func _resolve_anchor_collisions(anchors: Array[Vector2], min_gap: float) -> Array[Vector2]:
	var result := anchors.duplicate()
	var i := 0
	while i < result.size():
		var j := i
		while j + 1 < result.size() and result[j + 1].x - result[j].x < min_gap:
			j += 1
		if j > i:
			var cluster_center := 0.0
			for k in range(i, j + 1):
				cluster_center += result[k].x
			var count := j - i + 1
			cluster_center /= float(count)
			var start_x := cluster_center - min_gap * (count - 1) / 2.0
			for k in range(i, j + 1):
				result[k].x = start_x + (k - i) * min_gap
		i = j + 1
	return result

# The green edge half of Change 1 (2026-08-29) - reuses HudPalette.MAP_
# REACHABLE directly rather than mirroring it into a local export, same
# "direct-read consumer" convention _setup_region_name_label()'s own
# HudPalette.WORLD_TEXT read already establishes in this file: the brief was
# "adds the edges to [the existing green highlight]," so this has to
# track that SAME color if MAP_REACHABLE is ever retuned, not drift from
# it as a separately-eyeballed approximation would.
func _edge_color(from_current: bool) -> Color:
	return HudPalette.MAP_REACHABLE if from_current else dimmed_line_color

func _edge_width(from_current: bool) -> float:
	return reachable_line_width if from_current else line_width
