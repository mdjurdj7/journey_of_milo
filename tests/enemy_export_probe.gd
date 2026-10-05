extends SceneTree

# Headless probe for docs/enemy_export.json and the data it's built from:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/enemy_export_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
#   stale - the committed export is exactly what tests/enemy_export.gd
#           builds from the live data now (regenerate it when this fails)
#   gate  - on every floor FloorData.enemies[0] exists and is required:
#           RegionField._setup_exit_gate() places the gate off it
#   prose - every enemy has a mechanic_summary, every intent (and every
#           on_interrupt) an intent_name, and every status text in the
#           export resolved all its tokens

const CASES := 3
const EXPORT_PATH := "res://docs/enemy_export.json"

var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	_check_stale()
	_check_gate()
	_check_prose()
	if _completed != CASES:
		_failures += 1
		print("FAIL: only %d of %d cases ran to the end" % [_completed, CASES])
	if _failures == 0:
		print("enemy_export_probe: PASSED")
		quit(0)
	else:
		print("enemy_export_probe: %d FAILED" % _failures)
		quit(1)

func _check_stale() -> void:
	var file := FileAccess.open(EXPORT_PATH, FileAccess.READ)
	_expect(file != null, "%s exists" % EXPORT_PATH)
	if file != null:
		var committed: String = file.get_as_text().replace("\r\n", "\n")
		file.close()
		var built: String = EnemyExport.to_json()
		if committed != built:
			_fail("%s is stale - regenerate it: %s (first difference at line %d)" % [EXPORT_PATH, EnemyExport.REGENERATE, _first_difference(committed, built)])
	_completed += 1

func _check_gate() -> void:
	var regions: Array[RegionData] = EnemyExport.regions()
	_expect(not regions.is_empty(), "RegionField's scene names a region")
	for region in regions:
		for index in region.floors.size():
			var floor_data: FloorData = region.floors[index]
			var label: String = "%s floor %d" % [region.display_name, index + 1]
			if floor_data == null:
				_fail("%s is missing" % label)
				continue
			_expect(not floor_data.enemies.is_empty() and floor_data.enemies[0] != null, "%s places an enemy for its gate to measure from" % label)
			if not floor_data.enemies.is_empty() and floor_data.enemies[0] != null:
				_expect(floor_data.enemies[0].required, "%s: enemies[0], which the gate is placed off, is required" % label)
	_completed += 1

func _check_prose() -> void:
	var export: Dictionary = EnemyExport.build()
	for enemy: Dictionary in export["enemies"]:
		var name: String = enemy["name"]
		_expect(not String(enemy["mechanic_summary"]).strip_edges().is_empty(), "%s (%s) has a mechanic_summary" % [name, enemy["file"]])
		var moveset: Dictionary = enemy["moveset"]
		for intent: Dictionary in moveset["intents"]:
			_expect(not String(intent["name"]).is_empty(), "every %s intent has an intent_name" % name)
			if intent.has("interrupt") and intent["interrupt"]["on_interrupt"] != null:
				_expect(not String(intent["interrupt"]["on_interrupt"]["name"]).is_empty(), "%s's on_interrupt has an intent_name" % name)
		for status: Dictionary in enemy["statuses"]:
			_expect(not String(status["text"]).contains("{"), "%s's %s text resolves every token - got \"%s\"" % [name, status["name"], status["text"]])
	_completed += 1

func _first_difference(a: String, b: String) -> int:
	var lines_a: PackedStringArray = a.split("\n")
	var lines_b: PackedStringArray = b.split("\n")
	for index in mini(lines_a.size(), lines_b.size()):
		if lines_a[index] != lines_b[index]:
			return index + 1
	return mini(lines_a.size(), lines_b.size()) + 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: " + message)
