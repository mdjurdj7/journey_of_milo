extends RefCounted
class_name RunLogger

# The run's balance log: one JSON-lines file per run under user://runs/
# (on Windows, %APPDATA%\Godot\app_userdata\Journey of Milo\runs\), one
# line per event, flushed as each is written so a crash or a quit keeps
# everything up to it. tools/summarise_runs.py reads the folder.
#
# Static, so callers never need an instance - RunLogger.card_started(...)
# from anywhere. It names no autoload: everything it records is handed in
# (RunState.run_snapshot() for the run's state), so it compiles where the
# autoloads aren't registered yet (the headless probes).
#
# Read-only on the game: it never draws from RunState.rng or the global
# generator, and nothing reads anything back from it - switched off, the
# game plays exactly the same.
#
# Off in a headless instance - the probes start runs and load the field,
# and share this project's user:// - unless a probe points it at a folder
# of its own (set_output_dir()). RegionField.run_logging_enabled is the
# switch in the game.
#
# Events: run_start, floor_entered, fight_start, fight_end, run_end, and
# the reward-side ones written through reward_cards()/event(). A fight is
# summed here as it runs (damage, block, Toll, Grace, every card played)
# and written as one fight_end line.

const RUNS_DIR := "user://runs"
const FORMAT_VERSION := 1

# The switch - RegionField.run_logging_enabled pushes it here.
static var enabled: bool = true

# A probe's own folder; also what lets a headless instance write.
static var _output_dir: String = ""

static var _file: FileAccess = null
static var _path: String = ""
static var _start_msec: int = 0
# What makes a run worth keeping: a run that ends with neither (quit from
# the title) has its file deleted.
static var _fights: int = 0
static var _choices: int = 0
static var _region: int = 0
static var _floor: int = 0
static var _lap: int = 0
static var _last_encounter: String = ""
static var _last_fight_debug: bool = false

# --- The fight in progress ---
static var _fight_open: bool = false
static var _encounter: String = ""
static var _turn: int = 0
static var _hp_start: int = 0
static var _toll_start: int = 0
static var _taken_by: Dictionary = {} # source name -> HP lost to it
static var _taken_total: int = 0
static var _healed: int = 0
static var _grace_opened: int = 0
static var _grace_reclaimed: int = 0
static var _grace_lost: int = 0
static var _dealt: int = 0
static var _overkill: int = 0
static var _block_gained: int = 0
static var _block_used: int = 0
static var _absorb_used: int = 0
static var _toll_gained: int = 0
static var _toll_spent: int = 0
static var _enemy_hp: Dictionary = {} # Combatant instance id -> last HP seen
static var _cards: Array[Dictionary] = []

# --- The card resolving ---
static var _card_open: bool = false
static var _card_name: String = ""
static var _card_target: String = ""
static var _card_energy: int = 0
static var _card_hp_cost: int = 0
static var _card_self_lost: int = 0
static var _card_dealt: int = 0
static var _card_block: int = 0

# A probe's folder (user://...), which also lets a headless instance log.
# Empty puts it back to user://runs/ and the headless guard.
static func set_output_dir(dir: String) -> void:
	_output_dir = dir

static func is_run_open() -> bool:
	return _file != null

static func _active() -> bool:
	if not enabled:
		return false
	return not _output_dir.is_empty() or DisplayServer.get_name() != "headless"

# --- Run ---

# A new run's file and its first line. `snapshot` is RunState.run_snapshot().
static func start_run(seed: int, character_name: String, snapshot: Dictionary) -> void:
	_close()
	if not _active():
		return
	var dir: String = RUNS_DIR if _output_dir.is_empty() else _output_dir
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_path = dir.path_join("%s_s%d.jsonl" % [stamp, seed])
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("RunLogger: couldn't open %s for writing (error %d)." % [_path, FileAccess.get_open_error()])
		return
	print("RunLogger: writing %s" % ProjectSettings.globalize_path(_path))
	_start_msec = Time.get_ticks_msec()
	_fights = 0
	_choices = 0
	_last_encounter = ""
	_last_fight_debug = false
	_write("run_start", {
		"ts": Time.get_datetime_string_from_system(),
		"version": game_version(),
		"seed": seed,
		"class": character_name,
		"max_hp": snapshot.get("max_hp", 0),
		"deck": snapshot.get("deck", {}),
		"keepsake": snapshot.get("keepsake"),
	})

static func floor_entered(snapshot: Dictionary) -> void:
	_region = snapshot.get("region", 0)
	_floor = snapshot.get("floor", 0)
	_lap = snapshot.get("lap", 0)
	_write("floor_entered", {
		"region": _region,
		"floor": _floor,
		"lap": _lap,
		"hp": snapshot.get("hp", 0),
		"max_hp": snapshot.get("max_hp", 0),
		"gold": snapshot.get("gold", 0),
		"glassbone": snapshot.get("glassbone", 0),
		"toll": snapshot.get("toll", 0),
		"deck_size": snapshot.get("deck_size", 0),
		"keepsake": snapshot.get("keepsake"),
	})

# The run is over: `cause` is won (Region 1's last floor left by its
# exit), died, drowned, quit or abandoned (a new run started over one
# never ended). A death names the fight it was in. Every end carries the
# run's tally - fights won, floors crossed - and where it stood: HP of
# max, the deck and its size, keepsake, purse. A run with no fight and no
# reward choice in it is deleted rather than kept.
static func end_run(cause: String, snapshot: Dictionary) -> void:
	if _file == null:
		return
	var died: bool = cause == "died"
	_write("run_end", {
		"cause": cause,
		"encounter": or_null(_last_encounter if died else ""),
		"debug": _last_fight_debug if died else false,
		"region": snapshot.get("region", 0),
		"floor": snapshot.get("floor", 0),
		"lap": snapshot.get("lap", 0),
		"fights": _fights,
		"fights_won": snapshot.get("fights_won", 0),
		"floors_crossed": snapshot.get("floors_crossed", 0),
		"hp": snapshot.get("hp", 0),
		"max_hp": snapshot.get("max_hp", 0),
		"deck_size": snapshot.get("deck_size", 0),
		"final_deck": snapshot.get("deck", {}),
		"keepsake": snapshot.get("keepsake"),
		"gold": snapshot.get("gold", 0),
		"glassbone": snapshot.get("glassbone", 0),
	})
	var empty: bool = _fights == 0 and _choices == 0
	var path: String = _path
	_close()
	if empty:
		DirAccess.remove_absolute(path)
		print("RunLogger: nothing happened in that run; removed %s" % ProjectSettings.globalize_path(path))

# --- Fight ---

# "Dragonfly x3", "Dragonfly + Siltjaw": the enemies met, sorted, counted.
static func encounter_key(names: Array[String]) -> String:
	var counts: Dictionary = {}
	for enemy_name in names:
		counts[enemy_name] = int(counts.get(enemy_name, 0)) + 1
	var sorted: Array = counts.keys()
	sorted.sort()
	var parts: PackedStringArray = PackedStringArray()
	for enemy_name: String in sorted:
		var count: int = counts[enemy_name]
		parts.append(enemy_name if count == 1 else "%s x%d" % [enemy_name, count])
	return " + ".join(parts)

static func fight_start(encounter: String, enemy_ids: Array[String], snapshot: Dictionary) -> void:
	_fight_open = true
	_encounter = encounter
	_turn = 0
	_hp_start = snapshot.get("hp", 0)
	_toll_start = snapshot.get("toll", 0)
	_taken_by = {}
	_taken_total = 0
	_healed = 0
	_grace_opened = 0
	_grace_reclaimed = 0
	_grace_lost = 0
	_dealt = 0
	_overkill = 0
	_block_gained = 0
	_block_used = 0
	_absorb_used = 0
	_toll_gained = 0
	_toll_spent = 0
	_enemy_hp = {}
	_cards = []
	_card_open = false
	_fights += 1
	_write("fight_start", {
		"fight": _fights,
		"encounter": encounter,
		"enemies": enemy_ids,
		"region": _region,
		"floor": _floor,
		"lap": _lap,
		"hp": _hp_start,
		"max_hp": snapshot.get("max_hp", 0),
		"deck_size": snapshot.get("deck_size", 0),
		"deck": snapshot.get("deck", {}),
		"toll": _toll_start,
		"keepsake": snapshot.get("keepsake"),
	})

# The fight's end, whatever ended it: `result` win, lose or escape;
# `debug` when the F1 row's button did it.
static func fight_end(result: String, debug: bool, hp_end: int, toll_end: int) -> void:
	if not _fight_open:
		return
	card_finished()
	_fight_open = false
	_last_encounter = _encounter
	_last_fight_debug = debug
	_write("fight_end", {
		"fight": _fights,
		"encounter": _encounter,
		"result": result,
		"debug": debug,
		"turns": _turn,
		"hp_start": _hp_start,
		"hp_end": hp_end,
		"damage_taken": {"total": _taken_total, "by_source": _taken_by},
		"healed": _healed,
		"grace": {"opened": _grace_opened, "reclaimed": _grace_reclaimed, "lost": _grace_lost},
		"damage_dealt": {"total": _dealt, "overkill": _overkill},
		"block": {"gained": _block_gained, "used": _block_used, "absorb_used": _absorb_used},
		"toll": {"start": _toll_start, "gained": _toll_gained, "spent": _toll_spent, "end": toll_end},
		"cards": _cards,
	})

# The player's turn starts - the opening one included.
static func turn_started() -> void:
	if _fight_open:
		_turn += 1

# A card is committed: what it cost in Energy, and who it is aimed at
# ("" for none). Everything until card_finished() is its doing.
static func card_started(card_name: String, energy: int, target: String) -> void:
	if not _fight_open:
		return
	card_finished()
	_card_open = true
	_card_name = card_name
	_card_target = target
	_card_energy = energy
	_card_hp_cost = 0
	_card_self_lost = 0
	_card_dealt = 0
	_card_block = 0

static func card_finished() -> void:
	if not _card_open:
		return
	_card_open = false
	_cards.append({
		"turn": _turn,
		"card": _card_name,
		"energy": _card_energy,
		"hp_cost": _card_hp_cost,
		"hp_effect": maxi(_card_self_lost - _card_hp_cost, 0),
		"target": or_null(_card_target),
		"dealt": _card_dealt,
		"block": _card_block,
	})

# A card's price in HP (the stance's, a cost replacement's) - also counted
# as self-inflicted loss by player_hp_lost(); this splits it out.
static func hp_cost_paid(amount: int) -> void:
	if _card_open and amount > 0:
		_card_hp_cost += amount

# HP the run actually lost in the fight, and to what: an enemy's name,
# "self", or "status" (a tick).
static func player_hp_lost(amount: int, source: String) -> void:
	if not _fight_open or amount <= 0:
		return
	_taken_total += amount
	_taken_by[source] = int(_taken_by.get(source, 0)) + amount
	if _card_open and source == "self":
		_card_self_lost += amount

# HP the run actually got back in the fight, other than Grace.
static func player_healed(amount: int) -> void:
	if _fight_open and amount > 0:
		_healed += amount

static func grace_opened(amount: int) -> void:
	if _fight_open and amount > 0:
		_grace_opened += amount

static func grace_reclaimed(amount: int) -> void:
	if _fight_open and amount > 0:
		_grace_reclaimed += amount

static func grace_lost(amount: int) -> void:
	if _fight_open and amount > 0:
		_grace_lost += amount

# An enemy's HP as it now stands, for the overkill sum - at the fight's
# start and after anything heals it. `id` is its Combatant's instance id.
static func enemy_hp_seen(id: int, hp: int) -> void:
	if _fight_open:
		_enemy_hp[id] = hp

# Damage the player dealt to an enemy, as reported (DamagePipeline's
# damage_to_hp, which is not floored at what it had). What it actually
# lost counts; the rest is overkill.
static func damage_dealt(id: int, amount: int, hp_after: int) -> void:
	if not _fight_open or amount <= 0:
		return
	var actual: int = amount
	if hp_after <= 0 and _enemy_hp.has(id):
		var had: int = _enemy_hp[id]
		actual = clampi(had, 0, amount)
	_enemy_hp[id] = hp_after
	_dealt += actual
	_overkill += amount - actual
	if _card_open:
		_card_dealt += actual

static func block_gained(amount: int) -> void:
	if not _fight_open or amount <= 0:
		return
	_block_gained += amount
	if _card_open:
		_card_block += amount

# What the player's block and absorb took of an enemy attack.
static func block_used(blocked: int, absorbed: int) -> void:
	if not _fight_open:
		return
	_block_used += maxi(blocked, 0)
	_absorb_used += maxi(absorbed, 0)

# The run's Toll moved (RunState.set_toll()); in a fight, up is gained and
# down is spent.
static func toll_changed(before: int, after: int) -> void:
	if not _fight_open or before == after:
		return
	if after > before:
		_toll_gained += after - before
	else:
		_toll_spent += before - after

# --- Rewards and choices ---

# Cards put in front of the player and the one taken (null: skipped).
# `source`: fight, bundle, find.
static func reward_cards(source: String, offered: Array[CardData], taken: CardData) -> void:
	var names: Array[String] = []
	for card in offered:
		if card != null:
			names.append(card.card_name)
	event("reward_cards", {
		"source": source,
		"offered": names,
		"taken": or_null(taken.card_name if taken != null else ""),
	})

# Any other choice - reward_gold, reward_glassbone, belongings,
# keepsake_offer, trough - with where in the run it happened.
static func event(ev: String, data: Dictionary) -> void:
	if _file == null:
		return
	_choices += 1
	var line: Dictionary = {"region": _region, "floor": _floor, "lap": _lap}
	line.merge(data, true)
	_write(ev, line)

static func keepsake_id(trinket: TrinketData) -> Variant:
	return or_null(String(trinket.id) if trinket != null else "")

# JSON null for an empty name.
static func or_null(text: String) -> Variant:
	if text.is_empty():
		return null
	return text

# --- Version ---

# The short commit the game was run from, read from the project's .git
# (its HEAD, and the ref that names); "unknown" without one (an export).
# A worktree's .git is a file pointing at its own git dir, whose refs may
# live in the common dir.
static func game_version() -> String:
	var dot_git: String = ProjectSettings.globalize_path("res://").path_join(".git")
	var git_dir: String = dot_git
	if FileAccess.file_exists(dot_git):
		var pointer: String = FileAccess.get_file_as_string(dot_git).strip_edges()
		if not pointer.begins_with("gitdir:"):
			return "unknown"
		git_dir = _resolve_git_path(dot_git.get_base_dir(), pointer.substr(7).strip_edges())
	var head_path: String = git_dir.path_join("HEAD")
	if not FileAccess.file_exists(head_path):
		return "unknown"
	var head: String = FileAccess.get_file_as_string(head_path).strip_edges()
	if not head.begins_with("ref:"):
		return head.left(7) if head.length() >= 7 else "unknown"
	var ref: String = head.substr(4).strip_edges()
	var common_dir: String = git_dir
	var commondir_path: String = git_dir.path_join("commondir")
	if FileAccess.file_exists(commondir_path):
		common_dir = _resolve_git_path(git_dir, FileAccess.get_file_as_string(commondir_path).strip_edges())
	for dir in [git_dir, common_dir]:
		var ref_path: String = (dir as String).path_join(ref)
		if FileAccess.file_exists(ref_path):
			var hash: String = FileAccess.get_file_as_string(ref_path).strip_edges()
			if hash.length() >= 7:
				return hash.left(7)
	var packed_path: String = common_dir.path_join("packed-refs")
	if FileAccess.file_exists(packed_path):
		for line in FileAccess.get_file_as_string(packed_path).split("\n"):
			if line.strip_edges().ends_with(" " + ref):
				return line.left(7)
	return "unknown"

static func _resolve_git_path(base: String, path: String) -> String:
	return path if path.is_absolute_path() else base.path_join(path).simplify_path()

# --- File ---

static func _write(ev: String, data: Dictionary) -> void:
	if _file == null:
		return
	var line: Dictionary = {
		"v": FORMAT_VERSION,
		"ev": ev,
		"t": snappedf(float(Time.get_ticks_msec() - _start_msec) / 1000.0, 0.01),
	}
	line.merge(data, true)
	_file.store_line(JSON.stringify(line, "", false))
	_file.flush()

static func _close() -> void:
	if _file != null:
		_file.close()
	_file = null
	_path = ""
	_fight_open = false
	_card_open = false
