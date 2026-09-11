extends RefCounted
class_name CharacterPool
# Same "one small RefCounted helper scans a folder" shape as EncounterPool/
# EnemyPool (see encounter_pool.gd/enemy_pool.gd) - every .tres file in
# CHARACTER_FOLDER is a playable class. First (and so far only) reader is
# card_glossary.gd's character tab row: it builds one tab per entry here
# instead of hardcoding a button per known CharacterData (the way title_
# screen.gd's Dev Battle Chain or dev_encounter_picker.gd's ClassRow both
# still do) - specifically so a future third character needs nothing more
# than a new .tres dropped in this folder to show up there.

const CHARACTER_FOLDER := "res://resources/characters/"

static func list_all() -> Array[CharacterData]:
	var pool: Array[CharacterData] = []
	var dir := DirAccess.open(CHARACTER_FOLDER)
	if dir == null:
		# Same "missing folder isn't a crash" fallback as EncounterPool's
		# own list_all() - callers treat an empty result as "nothing here."
		return pool
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			pool.append(load(CHARACTER_FOLDER + file_name))
	pool.sort_custom(func(a: CharacterData, b: CharacterData): return a.character_name < b.character_name)
	return pool
