extends SceneTree

# Headless probe for the run log's empty-run rule (RunLogger.end_run()):
# a run closed with no fight and no reward choice in it leaves no file;
# a run with one is kept, closed with its run_end. Driven through
# RunState.new_run(), the way the character select replaces the run the
# title was held on - the replaced run is closed "abandoned" and, empty,
# removed:
#
#   empty   - a run, then another started over it: the first's file is
#             gone, the second's is there
#   kept    - a choice in the second (an event line), then a third run
#             over it: the second's file stays, ending on its run_end
#             ("abandoned"); the third's is there too
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/run_log_empty_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload.

const CASES := 2
const LOG_DIR := "user://run_log_empty_probe"
const WANDERER_PATH := "res://run/data/wanderer.tres"
const SAMURAI_PATH := "res://run/data/samurai.tres"

# This process's log folder: run_probes.sh's per-process --runlog-dir
# (RunLogger.dir_override()) when it hands one over, so a second copy of
# this probe running at once never sees this one's files - else LOG_DIR.
var _log_dir: String = RunLogger.dir_override() if not RunLogger.dir_override().is_empty() else LOG_DIR
var _failures: int = 0
var _completed: int = 0
var _run_state: Node = null

func _initialize() -> void:
	_run_state = root.get_node("RunState")
	_clear_dir()
	RunLogger.set_output_dir(_log_dir)
	_check_empty_run_removed()
	_check_run_with_choice_kept()
	# The last run open is closed and, empty, removed; the folder is left
	# as the cases left it otherwise.
	_run_state.call("log_run_end", "quit")
	RunLogger.set_output_dir("")
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("run_log_empty_probe: PASSED")
		quit(0)
	else:
		print("run_log_empty_probe: %d FAILED" % _failures)
		quit(1)

func _check_empty_run_removed() -> void:
	_run_state.call("new_run", load(WANDERER_PATH))
	var first: Array[String] = _files()
	_expect_eq(first.size(), 1, "A run writes one file")
	_run_state.call("new_run", load(SAMURAI_PATH))
	var second: Array[String] = _files()
	_expect_eq(second.size(), 1, "A run started over an empty one leaves one file")
	if first.size() == 1:
		_expect(not second.has(first[0]), "...and it isn't the replaced run's (%s)" % first[0])
	_completed += 1

func _check_run_with_choice_kept() -> void:
	var before: Array[String] = _files()
	RunLogger.event("probe_choice", {})
	_run_state.call("new_run", load(WANDERER_PATH))
	var after: Array[String] = _files()
	_expect_eq(after.size(), 2, "A run with a choice in it is kept beside the new one")
	if before.size() == 1 and after.has(before[0]):
		var lines: PackedStringArray = FileAccess.get_file_as_string(_log_dir.path_join(before[0])).strip_edges().split("\n")
		var last := JSON.parse_string(lines[lines.size() - 1]) as Dictionary
		_expect(last != null and last.get("ev") == "run_end", "...ending on its run_end")
		_expect(last != null and last.get("cause") == "abandoned", "...closed as abandoned")
	else:
		_fail("The run with a choice in it kept its file (%s)" % str(before))
	_completed += 1

# --- Helpers ---

func _files() -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(_log_dir):
		if file.ends_with(".jsonl"):
			found.append(file)
	return found

func _clear_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_log_dir)
	for file in DirAccess.get_files_at(_log_dir):
		DirAccess.remove_absolute(_log_dir.path_join(file))

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
