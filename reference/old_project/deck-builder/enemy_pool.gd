extends RefCounted
class_name EnemyPool
# The bestiary: every .tres file in ENEMY_FOLDER is a valid enemy. Used
# both by room_state.gd (deciding which enemy a field blob represents,
# before the player ever reaches battle - see its _generate_combat_layout()/
# _generate_boss_layout()) and battle.gd (falling back to a fresh random
# pick for the "Dev: Battle Chain" shortcut, which skips the field
# entirely - see title_screen.gd). One place (list_all() below) scans the
# folder so every caller agrees on what "the bestiary" is - same "one
# small RefCounted helper" shape as WeightedRandom/RunNode.

const ENEMY_FOLDER := "res://resources/enemies/"
const OPENING_ENEMY_FOLDER := "res://resources/enemies/opening/"
# Unrelieved's own folder now (2026-08-29, "Tideworn as a real encounter"
# pass) - Tideworn moved OUT to resources/enemies/ itself (see room_
# state.gd's OPENING_ROOM_ENEMY doc), so it's a normal member of the main
# pool now, same as Beachwrack/Outbound. Unrelieved stays here,
# deliberately kept out of list_all()'s default scan (include_opening=
# false) the same way both of them used to be - it's still EXPERIMENTAL/
# dev-buttons-only (see RoomState.opening_room_variant), with no ask yet
# to change that. Only dev_encounter_picker.gd passes true (see its own
# header) - a dev iterating on Unrelieved specifically has a real reason
# to reach it directly; an ordinary random encounter still shouldn't.
const ENCOUNTER_ONLY_ENEMY_FOLDER := "res://resources/enemies/encounter_only/"
# Same shape as OPENING_ENEMY_FOLDER above, for a different reason: the
# Mushroom (see enemy_data.gd's growth_stage_track_length doc) has no
# sensible identity as an independent solo roll - its growth_start_stage
# stagger only means anything authored alongside its own two siblings in
# mushroom_patch.tres (see resources/encounters/sunken_works/). Unlike
# Glasswing (independently rollable AND reused twice in Twin Glasswings),
# a Mushroom dropped into an ordinary combat room alone would just erupt
# on a hardcoded stagger nothing else there justifies. Simply placing the
# .tres files here was the actual bug once (2026-08-26) - list_all()'s
# default excluding this folder is what keeps a solo mushroom from ever
# being rolled again, not a convention anyone has to remember to follow
# per-file.
const BOSS_ENEMY_FOLDER := "res://resources/enemies/bosses/"
# Same idiom again, third time (2026-08-29, BOSS_01 pass): a dedicated
# boss (see EnemyData's own Charge section) has no sensible identity as
# an ordinary combat/elite roll either - it's meant to be reached exactly
# one way, room_state.gd's own _generate_boss_layout() loading it
# directly by path, never through this pool at all. list_all()'s default
# excluding this folder is what keeps a boss from ever being solo-rolled
# into a normal fight, same "excluded by construction, not by a
# convention someone has to remember" guarantee the other two folders
# already give their own contents.

# One place scans each folder, reused by pick_random() below AND by
# dev_encounter_picker.gd's Mode 2 (2026-08-27, dev-encounter-picker
# pass - see that file's own header) - previously only pick_random()
# needed the full pool, inline; a second caller wanting the same list
# (not a single weighted pick out of it) is what pulled the scan itself
# out into its own function.
static func list_all(include_opening: bool = false, include_encounter_only: bool = false, include_bosses: bool = false) -> Array[EnemyData]:
	var pool: Array[EnemyData] = []
	_scan_folder(ENEMY_FOLDER, pool)
	if include_opening:
		_scan_folder(OPENING_ENEMY_FOLDER, pool)
	if include_encounter_only:
		_scan_folder(ENCOUNTER_ONLY_ENEMY_FOLDER, pool)
	if include_bosses:
		_scan_folder(BOSS_ENEMY_FOLDER, pool)
	return pool

static func _scan_folder(folder: String, pool: Array[EnemyData]) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			pool.append(load(folder + file_name))

# Weighted, not a flat pick_random() over the folder - every enemy's own
# EnemyData.pool_weight decides its odds (see enemy_data.gd), same
# technique room_state.gd's room-type roll already uses (see
# weighted_random.gd). Every enemy defaults to weight 1.0 (equal odds,
# what a uniform pick_random() over the folder already did), so this is
# only a behavior change for whichever enemy is deliberately tuned rarer
# (the Wardling, at 0.5 against everything else's 1.0 - see
# wardling.tres).
# current_layer defaults high enough (999) that EnemyData.min_layer -
# small numbers like Outbound's 4, always <= 999 - never filters anyone
# out unless a caller passes the run's REAL current layer (see room_
# state.gd's _generate_combat_layout()), so every other existing caller
# (the boss roll, battle.gd's Dev Battle Chain fallback) keeps today's
# unfiltered behavior for free, without needing a separate sentinel.
#
# allow_escape mirrors allow_elite's own shape - false excludes any
# enemy with EnemyData.escape_distance_max > 0.0 (today: only Outbound)
# from the pool entirely, same "excluded, not rolled-then-clamped"
# filtering as everything else here. Used by the boss roll specifically
# (see room_state.gd's _generate_boss_layout()) - a boss that could flee
# the fight it's meant to be the run's climax of was a deliberate no.
static func pick_random(allow_elite: bool = true, current_layer: int = 999, allow_escape: bool = true) -> EnemyData:
	var pool: Array[EnemyData] = list_all()
	var weights: Dictionary = {}
	for enemy_data: EnemyData in pool:
		if enemy_data.is_elite and not allow_elite:
			continue
		if enemy_data.min_layer > current_layer:
			continue
		if enemy_data.escape_distance_max > 0.0 and not allow_escape:
			continue
		weights[enemy_data] = enemy_data.pool_weight
	if weights.is_empty():
		# Every enemy in the folder was elite (e.g. a bestiary of one, mid-
		# development) - fall back to the unfiltered pool rather than
		# returning null and crashing whatever called this.
		push_warning("EnemyPool: allow_elite=false left no non-elite enemies - falling back to the full pool.")
		for enemy_data: EnemyData in pool:
			weights[enemy_data] = enemy_data.pool_weight
	return WeightedRandom.pick(weights)
