extends Control
class_name PlayerResourceCluster
# The player's grouped resource readout - energy pips on top, Toll
# directly below. Replaces two previously-unrelated pieces of HUD: the
# energy pips (resource_display.tscn, anchored on its own near the hand)
# and TollDisplay (previously instanced inside player_battle_visual.tscn,
# well away from the pips) - both are player resources, and read as two
# unrelated things sitting in unrelated places. See DESIGN.md's Toll
# entry ("Promoted into a real player-resource cluster") for the fuller
# history.
#
# Same "Battle owns the numbers, this only displays them" split every
# other HUD piece here already follows - battle.gd calls update_energy()/
# update_toll(), never reaches into energy_display/toll_display
# directly.
#
# NO BACKING PANEL (REMOVED 2026-08-25) - a Background ColorRect
# grouped the two by sitting behind both, tried at two opacities (0.55,
# then 0.18) and dropped outright rather than tuned further: the
# grouping itself is carried by position alone (pips directly above
# Toll, both left-aligned to the same inset), the same way this project
# already groups related HUD elements elsewhere without a box (RoomLabel/
# BattleLabel/TurnLabel/GoldLabel/ClassLabel read as one cluster purely
# from being stacked, no panel of their own - InfoLabelBackground behind
# THEM exists for THEIR OWN separate reason, sitting directly over
# variable backdrop art with no other legibility help, which doesn't
# apply here).
#
# SIZED FROM REAL CONTENT (2026-08-25 fix), not a hand-picked constant -
# the first pass used fixed cluster_width_px/cluster_height_px exports,
# hand-computed against pip/Toll geometry with zero margin, which is
# exactly why the Toll value ended up clipped at the cluster's own
# bottom edge the moment real font metrics didn't match the guess
# precisely. _apply_layout() below now reads each child's own ACTUAL
# size (Toll's own measured row heights - see toll_display.gd's
# _layout_row() - and the pip row's real combined minimum size) and
# adds content_padding_px on every side, so "clipped/cramped" can't
# happen from a stale constant again.

@export var content_padding_px: float = 14.0
# No longer padding against a visible panel edge (see this file's own
# header) - just breathing room from this Control's own origin, so
# neither row starts flush against local (0,0).
@export var row_gap_px: float = 20.0
# Gap between the pip row's bottom edge and TollDisplay's own top edge -
# same role as player_battle_visual.gd's old toll_row_gap_px, just
# between these two rows now instead of the HP bar and Toll.

const ENERGY_ROW_HEIGHT_PX := 50.0
# Matches resource_display.tscn's own baked custom_minimum_size.y -
# fixed regardless of pip count (only the row's WIDTH depends on how
# many pips there are), so this is safe to hardcode rather than read
# back from energy_display at runtime.

@onready var energy_display: ResourceDisplay = $EnergyDisplay
@onready var toll_display: TollDisplay = $TollDisplay

func _ready() -> void:
	_apply_layout()

# Both rows left-aligned to the SAME inset - neither can ever shift the
# other regardless of how wide either one's own content gets (Toll
# growing from 1 to 3 digits included - see toll_display.gd's own
# value_column_width_px doc), since neither position is derived from
# the other's current size. Re-run from update_energy() below, not just
# _ready() - the pip row doesn't exist the first time this runs (Godot's
# bottom-up ready order means every node under this one is already
# ready before this _ready() body executes, but EnergyDisplay's own pip
# row is only ever populated by a real update() call, which happens
# later, from Battle's own _ready()) - re-running afterward is what
# makes the panel's WIDTH correct once pips actually exist, not just an
# initial guess with nothing in the row yet.
func _apply_layout() -> void:
	energy_display.position = Vector2(content_padding_px, content_padding_px)
	toll_display.position = Vector2(content_padding_px, content_padding_px + ENERGY_ROW_HEIGHT_PX + row_gap_px)

	# get_combined_minimum_size(), NOT pip_row.size - a Container's own
	# .size only reflects an actual layout pass, which isn't guaranteed
	# to have run yet the instant _rebuild_pips() returns (verified
	# headlessly: .size read stale/baked here, get_combined_minimum_size()
	# read the correct, real pip-row width immediately, same frame).
	var pip_row_width: float = energy_display.pip_row.get_combined_minimum_size().x
	var content_width: float = maxf(pip_row_width, toll_display.size.x)
	var content_height: float = ENERGY_ROW_HEIGHT_PX + row_gap_px + toll_display.size.y

	custom_minimum_size = Vector2(content_width + content_padding_px * 2.0, content_height + content_padding_px * 2.0)
	size = custom_minimum_size

func update_energy(current: int, max_value: int) -> void:
	energy_display.update(current, max_value)
	_apply_layout()

func update_toll(value: int) -> void:
	toll_display.update_toll(value)
