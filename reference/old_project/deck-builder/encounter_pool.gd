extends RefCounted
class_name EncounterPool
# The same shape as EnemyPool (see enemy_pool.gd), but for AUTHORED
# multi-enemy encounters (see encounter_data.gd and DESIGN.md's Bestiary:
# Authored encounters) - every .tres in a given folder is a deliberately
# composed group, picked here the same weighted way EnemyPool already
# picks a single enemy. Two separate tables share this same mechanism
# (see DESIGN.md's ELITE Rooms section):
#
# - ENCOUNTER_FOLDER (the default) - room_state.gd's ordinary combat
#   blobs reach for this a fraction of the time (see its encounter_
#   chance); most blobs still roll a single enemy through EnemyPool
#   unchanged. Empty right now - ready for the next non-elite authored
#   encounter.
# - ELITE_ENCOUNTER_FOLDER - the ONLY way an ELITE room's fight gets
#   picked (see room_state.gd's _generate_elite_layout()). A single-
#   enemy elite (the Wardling) is still an EncounterData here, just
#   with one entry in its enemies array - see wardling_solo.tres.
const ENCOUNTER_FOLDER := "res://resources/encounters/"
const ELITE_ENCOUNTER_FOLDER := "res://resources/encounters/elite/"

# One place scans a given folder, reused by pick_random() below AND by
# dev_encounter_picker.gd's Mode 1 (2026-08-27, dev-encounter-picker
# pass - see that file's own header), which calls this once per folder
# (ENCOUNTER_FOLDER, then ELITE_ENCOUNTER_FOLDER) to build two separately
# labeled groups rather than one merged list - the picker needs to mark
# elite entries, which folder they came from is the only signal for
# that (EncounterData itself has no is_elite field of its own).
static func list_all(folder: String = ENCOUNTER_FOLDER) -> Array[EncounterData]:
	var pool: Array[EncounterData] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		# No encounters authored yet in this folder (or it's missing) -
		# callers treat an empty result as "nothing here," same fallback
		# shape pick_random() below already uses.
		return pool
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			pool.append(load(folder + file_name))
	return pool

static func pick_random(folder: String = ENCOUNTER_FOLDER) -> EncounterData:
	var pool: Array[EncounterData] = list_all(folder)
	if pool.is_empty():
		# No encounters authored yet in this folder (or it's missing) -
		# callers treat null as "roll a normal single enemy instead," so
		# this is a safe, silent fallback rather than a crash.
		return null
	var weights: Dictionary = {}
	for encounter: EncounterData in pool:
		weights[encounter] = encounter.pool_weight
	return WeightedRandom.pick(weights)
