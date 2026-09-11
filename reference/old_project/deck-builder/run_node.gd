extends RefCounted
class_name RunNode
# One slot in the run's graph (see run_state.gd's _generate_run_graph()) -
# a single room at a fixed layer, with the room type it'll be when the
# player reaches it and the forward edges (to next-layer nodes) the player
# can walk through to leave it. Same RefCounted shape as WeightedRandom/
# LootEntry: a plain in-memory object, never saved to disk - the graph is
# rebuilt from scratch every run, not something that needs to persist
# between sessions.
#
# The graph itself is a DAG: edges only ever point from layer N to layer
# N+1, never sideways or backward - see run_state.gd for how that's built
# and guaranteed fully connected.

var room_type: RoomType.Kind = RoomType.Kind.COMBAT
# Placeholder until RunState's _assign_room_types() runs and overwrites
# this - every node gets a real type before the graph is ever used.

var display_name: String = ""
# Always "" today (2026-08-31, label-unification pass - RunState used to
# assign this a per-biome flavor name for the map at generation time; see
# run_state.gd's own _assign_room_types() doc for why that pass was
# removed). Left in place, unset, rather than deleted - map_screen.gd's
# _node_label() already treats "" as "no override, use the plain room-
# type label" (now RoomType.display_name()), so a future per-node name
# (a per-biome variant, an authored beat) could still hang this field
# without that call site changing again.

var layer: int # 0-indexed: layer 0 is the run's start, the last layer is the boss.
var index_in_layer: int
var id: String # e.g. "L1_0" - human-readable, used by the dev graph print.

var connections: Array[RunNode] = []
# This node's forward edges - which layer-(layer+1) node(s) each door in
# this room leads to (see field_room.gd's _spawn_exits()). Empty only for
# the final layer's node - the boss room has no exit.

func _init(p_layer: int, p_index_in_layer: int) -> void:
	layer = p_layer
	index_in_layer = p_index_in_layer
	id = "L%d_%d" % [p_layer + 1, p_index_in_layer] # +1: layers print/read as 1-indexed.
