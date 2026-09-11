extends Resource
class_name SiftOutcomeTable
# A wreckage heap's full pool of possible pulls (2026-08-28, wreckage-heap
# room v1) - a thin wrapper Resource purely so the pool can be authored
# and edited as one .tres with embedded SiftOutcomeData sub-resources
# (same "flat @export array of resources" shape EncounterData.enemies
# already uses), rather than a Dictionary literal living inside a script.
# One shared instance today (see resources/wreckage_heap/sift_outcomes.
# tres, referenced by every field_heap.gd instance's own sift_outcome_
# table export) - nothing here assumes there will only ever be one table,
# just that indices into THIS array are what RunState.sift_outcomes_drawn
# tracks (see its own doc).

@export var entries: Array[SiftOutcomeData] = []
