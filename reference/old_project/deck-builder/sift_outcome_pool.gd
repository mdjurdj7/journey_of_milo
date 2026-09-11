extends RefCounted
class_name SiftOutcomePool
# Draw-without-replacement over a SiftOutcomeTable (2026-08-28, wreckage-
# heap room v1 brief) - same "static WeightedRandom.pick() over a
# filtered dictionary" shape run_state.gd's own _pick_blob_count() already
# uses to exclude options rather than clamp after picking.
#
# Indices, not SiftOutcomeData references, are what gets tracked (see
# RunState.sift_outcomes_drawn's own doc) - draw() maps the table's array
# positions to weights, filters out whatever `drawn` already has, and
# hands the pick straight back as the resource itself for the caller to
# read text/cost/effect off of.
#
# `drawn` TAKES the already-drawn set as a parameter now (2026-09-01,
# pool-scoping pass) - REPLACES a hardcoded read/write of RunState.sift_
# outcomes_drawn, which forced every draw-without-replacement pool in the
# game to share ONE run-scoped set whether that made sense for it or not.
# GDScript Arrays are reference types (append() here mutates the caller's
# own array in place, the same way a Dictionary or another Array passed
# around this codebase always aliases rather than copies), so the caller
# decides what "drawn so far" means simply by which array it hands in -
# RunState.sift_outcomes_drawn for a pool meant to persist across every
# instance this run (field_heap.gd's SiftPoolScope.PER_RUN), or a plain
# per-instance Array[int] for one that shouldn't (SiftPoolScope.PER_
# INSTANCE) - see field_heap.gd's own _drawn_list() for the one caller
# that picks between the two today. This function itself has no opinion
# on which - it just reads and appends to whatever it's given.

# Returns null once every entry in `table` has already been drawn against
# `drawn` (2026-08-28 decision: exhausted means no more pulls, not a
# reshuffle - see this feature's own report) - field_heap.gd's own click
# handler is expected to treat null as "nothing left to find here."
static func draw(table: SiftOutcomeTable, drawn: Array[int]) -> SiftOutcomeData:
	var weights: Dictionary = {}
	for i in table.entries.size():
		if not drawn.has(i):
			weights[i] = table.entries[i].weight
	if weights.is_empty():
		return null
	var picked_index: int = WeightedRandom.pick(weights)
	drawn.append(picked_index)
	return table.entries[picked_index]
