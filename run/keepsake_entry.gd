extends Resource
class_name KeepsakeEntry

# One line of a source's KeepsakeTable: the trinket, its weight against
# the table's other lines, and whether it can come up at most once a run.

@export var trinket: TrinketData = null
@export var weight: float = 1.0
# Once offered - taken or left - it never comes up again this run
# (RunState.keepsakes_offered).
@export var unique_per_run: bool = false
