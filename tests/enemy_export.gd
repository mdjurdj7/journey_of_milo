extends SceneTree
class_name EnemyExport

# Writes docs/enemy_export.json - every enemy encounter as it's placed,
# region by region, floor by floor (RegionData order), plus each enemy data
# file once - from the live data, never by hand:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/enemy_export.gd
#
# Deterministic: no timestamp, no commit, keys in a fixed order - the same
# data always writes the same bytes, so tests/enemy_export_probe.gd can
# fail the moment the committed file is stale (it compares to_json()).
# The prose comes from the data too: EnemyData.mechanic_summary,
# EnemyIntent.intent_name, and each status's description resolved through
# Status.describe().
#
# It refuses to write (exit 1, nothing touched) when the project didn't
# load cleanly - an import left unfinished, or a resource the export reads
# missing (load_problems()) - or when the export would have more than
# --max-shrink=<fraction> (default DEFAULT_MAX_SHRINK) fewer floors,
# encounters or enemies than the committed file (shrink_problems()). A
# half-imported tree once wrote a near-empty export. For an intended large
# removal, pass --allow-shrink:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/enemy_export.gd -- --allow-shrink

const OUTPUT_PATH := "res://docs/enemy_export.json"
const OUTPUT_GIT_PATH := "docs/enemy_export.json"
const DEFAULT_MAX_SHRINK := 0.2
const ALLOW_SHRINK_FLAG := "--allow-shrink"
const MAX_SHRINK_ARG := "--max-shrink="
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const REWARD_SCREEN_SCENE_PATH := "res://battle/reward_screen.tscn"
const ENEMY_DIR := "res://battle/rules/enemies/"
const FIELD_ENEMY_SCRIPT_PATH := "res://field/field_enemy.gd"
const REGENERATE := "Godot_v4.7.1.exe --headless --path . -s res://tests/enemy_export.gd"
# StatusData fields the export never lists as numbers: names and prose,
# shown elsewhere in the entry, and its presentation.
const STATUS_SKIP: Array[String] = ["id", "display_name", "description", "battle_animation", "script", "resource_local_to_scene", "resource_path", "resource_name", "resource_scene_unique_id"]

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var max_shrink: float = DEFAULT_MAX_SHRINK
	for arg in args:
		if arg.begins_with(MAX_SHRINK_ARG):
			max_shrink = arg.trim_prefix(MAX_SHRINK_ARG).to_float()
	var problems: Array[String] = load_problems()
	if not problems.is_empty():
		_refuse(problems, "the project didn't load cleanly. Re-import it (Godot_v4.7.1.exe --headless --path . --import) and run this again.")
		return
	var export: Dictionary = build()
	var committed: Variant = _committed_export()
	if committed == null:
		print("enemy_export: no committed %s to compare against - writing it fresh" % OUTPUT_PATH)
	elif not args.has(ALLOW_SHRINK_FLAG):
		problems = shrink_problems(export, committed as Dictionary, max_shrink)
		if not problems.is_empty():
			_refuse(problems, "it would shrink sharply. If the removal is intended, pass %s after --." % ALLOW_SHRINK_FLAG)
			return
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		print("enemy_export: could not write %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(_stringify(export))
	file.close()
	print("enemy_export: wrote %s" % OUTPUT_PATH)
	quit(0)

func _refuse(problems: Array[String], why: String) -> void:
	for problem in problems:
		print("enemy_export: REFUSED - " + problem)
	print("enemy_export: nothing written to %s - %s" % [OUTPUT_PATH, why])
	quit(1)

static func to_json() -> String:
	return _stringify(build())

static func _stringify(export: Dictionary) -> String:
	return JSON.stringify(export, "  ", false) + "\n"

# What would make the export a lie: an import that didn't finish (an
# imported file missing from .godot/imported, or an asset never imported),
# or a resource the export reads that doesn't load. build() skips nulls
# quietly, so without this a broken tree writes a gutted export. Empty =
# clean.
static func load_problems() -> Array[String]:
	var problems: Array[String] = _import_problems()
	var listed: Array[RegionData] = regions()
	if listed.is_empty():
		problems.append("%s didn't load, or names no region" % REGION_SCENE_PATH)
	for region in listed:
		if region.floors.is_empty():
			problems.append("%s has no floors" % region.resource_path)
		for index in region.floors.size():
			var floor_data: FloorData = region.floors[index]
			if floor_data == null:
				problems.append("%s floor %d didn't load" % [region.resource_path, index + 1])
				continue
			for slot in floor_data.slots:
				if slot == null:
					problems.append("%s has a slot that didn't load" % floor_data.resource_path)
					continue
				for option in slot.options:
					if option == null:
						problems.append("%s slot %s has an option that didn't load" % [floor_data.resource_path, slot.slot_id])
						continue
					for entry in option.members:
						if entry == null or entry.enemy_data == null:
							problems.append("%s slot %s option %s has a member whose enemy didn't load" % [floor_data.resource_path, slot.slot_id, option.option_id])
	var enemy_paths: Array[String] = _enemy_paths()
	if enemy_paths.is_empty():
		problems.append("no enemy files in %s" % ENEMY_DIR)
	for path in enemy_paths:
		if not (load(path) is EnemyData):
			problems.append("%s didn't load as EnemyData" % path)
	if _scene_root_property(REWARD_SCREEN_SCENE_PATH, "choice_count") == null:
		problems.append("%s didn't load, or has no choice_count" % REWARD_SCREEN_SCENE_PATH)
	if not (load(FIELD_ENEMY_SCRIPT_PATH) is Script):
		problems.append("%s didn't load" % FIELD_ENEMY_SCRIPT_PATH)
	return problems

# Every .import's dest_files exist, and every file of a kind the project
# imports has its .import - outside .gdignore'd folders.
static func _import_problems() -> Array[String]:
	var problems: Array[String] = []
	var files: Array[String] = []
	_collect_files("res://", files)
	var imported_kinds: Dictionary = {}
	var has_import: Dictionary = {}
	for path in files:
		if not path.ends_with(".import"):
			continue
		var source: String = path.trim_suffix(".import")
		has_import[source] = true
		imported_kinds[source.get_extension().to_lower()] = true
		var config := ConfigFile.new()
		if config.load(path) != OK:
			problems.append("%s can't be read" % path)
			continue
		var dest_files: Variant = config.get_value("deps", "dest_files", [])
		if not dest_files is Array:
			continue
		for dest: Variant in dest_files:
			if not FileAccess.file_exists(String(dest)):
				problems.append("%s isn't imported (%s is missing)" % [source, dest])
				break
	if imported_kinds.is_empty():
		problems.append("no .import files under res:// - the project was never imported")
	for path in files:
		if imported_kinds.has(path.get_extension().to_lower()) and not has_import.has(path):
			problems.append("%s was never imported (no .import beside it)" % path)
	return problems

static func _collect_files(dir: String, out: Array[String]) -> void:
	if FileAccess.file_exists(dir.path_join(".gdignore")):
		return
	for file_name in DirAccess.get_files_at(dir):
		out.append(dir.path_join(file_name))
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_collect_files(dir.path_join(sub), out)

# The export at HEAD (git show), else the file on disk; null when neither
# exists. An unreadable one is an empty Dictionary, so every count drops.
static func _committed_export() -> Variant:
	var text: String = ""
	var output: Array = []
	var root: String = ProjectSettings.globalize_path("res://")
	if OS.execute("git", ["-C", root, "show", "HEAD:" + OUTPUT_GIT_PATH], output) == 0 and not output.is_empty():
		text = String(output[0])
	elif FileAccess.file_exists(OUTPUT_PATH):
		text = FileAccess.get_file_as_string(OUTPUT_PATH)
	else:
		return null
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

# The export's floors, encounters and enemies against the committed one's:
# a problem for each that drops by more than max_shrink (a fraction).
static func shrink_problems(export: Dictionary, committed: Dictionary, max_shrink: float) -> Array[String]:
	var problems: Array[String] = []
	var now: Dictionary = entry_counts(export)
	var before: Dictionary = entry_counts(committed)
	for key: String in now:
		var had: int = before[key]
		var has: int = now[key]
		if had > 0 and float(has) < float(had) * (1.0 - max_shrink):
			problems.append("%s: %d now, %d committed (more than %d%% fewer)" % [key, has, had, roundi(max_shrink * 100.0)])
	return problems

static func entry_counts(export: Dictionary) -> Dictionary:
	var floors: int = 0
	var encounters: int = 0
	var regions: Variant = export.get("regions", [])
	if regions is Array:
		for region: Variant in regions:
			var region_floors: Variant = (region as Dictionary).get("floors", []) if region is Dictionary else []
			if not region_floors is Array:
				continue
			for floor_entry: Variant in region_floors:
				floors += 1
				var floor_encounters: Variant = (floor_entry as Dictionary).get("encounters", []) if floor_entry is Dictionary else []
				if floor_encounters is Array:
					encounters += (floor_encounters as Array).size()
	var enemies: Variant = export.get("enemies", [])
	return {
		"floors": floors,
		"encounters": encounters,
		"enemies": (enemies as Array).size() if enemies is Array else 0,
	}

# The regions RegionField plays: its scene's own `regions` export, in
# order.
static func regions() -> Array[RegionData]:
	var found: Array[RegionData] = []
	var listed: Variant = _scene_root_property(REGION_SCENE_PATH, "regions")
	if listed is Array:
		for entry: Variant in listed:
			var region := entry as RegionData
			if region != null:
				found.append(region)
	return found

static func build() -> Dictionary:
	var appearances: Dictionary = {}
	var region_list: Array = []
	var region_index: int = 0
	for region in regions():
		region_list.append(_region_entry(region, region_index, appearances))
		region_index += 1
	var roster: Array = []
	for path in _enemy_paths():
		var data := load(path) as EnemyData
		if data != null:
			var appears_on: Array = appearances.get(path, [])
			roster.append(_enemy_entry(data, appears_on))
	return {
		"export_info": {
			"description": "Generated export of every enemy encounter as placed in each FloorData, by region and floor in RegionData order, and every enemy data file once (enemies). Never edit by hand - regenerate it; tests/enemy_export_probe.gd fails when this file is stale.",
			"regenerate": REGENERATE,
			"generated_from": [
				REGION_SCENE_PATH + " (its region and encounter_rewards_path)",
				"res://floors/*.tres (RegionData, FloorData, EncounterSlot, EncounterOption, FloorEnemy, FloorPatrol, FloorProp)",
				ENEMY_DIR + "*.tres (EnemyData, EnemyIntent)",
				"res://battle/rules/statuses/*.tres (StatusData, resolved through Status.describe())",
				"res://run/keepsakes/*.tres (KeepsakeTable, TrinketData)",
				"res://run/armor/*.tres (KeepsakeTable, TrinketData - worn pieces)",
				"res://cards/pools/*.tres (RewardPool rarity rates)",
				"res://run/fight_rarity_by_floor.tres (FightRarityTable - a normal fight's rarity rates by floor, through EncounterRewards)",
				REWARD_SCREEN_SCENE_PATH + " (choice_count)",
			],
			"positions": "World XZ offsets from the floor's spawn, metres ([x, z]) - an option's members and props mapped through their slot (EncounterSlot.to_floor()).",
			"encounters": "One entry per option of each EncounterSlot, in slot order: the slot is where (anchor, required), the option is who (members, their props, their route). One option per slot is stood each floor load. A cluster is an option of more than one member; its name is its slot's id.",
			"required": "EncounterSlot.required: the floor is cleared, and its gate opens, once no member of a required slot stands.",
			"gate_fight": "The floor's first required slot: RegionField._setup_exit_gate() places the gate gate_distance_beyond_enemy past its anchor, along exit_direction, whichever option stands there.",
			"elite": "EnemyData.is_elite. A fight with an elite in it pays the floor's gold times its role's gold_multiplier in EncounterRewards (the elite's, rounded) and rolls its card at the pool's elite rarity rates. A placement marked FloorEnemy.card_reward TOP_TIER_FIRST (floor 5's region-end Greyshelf) offers its cards from the highest tier down instead (RewardPool.roll_top_tier()), at the floor's gold. See each encounter's elite_rewards. Keepsakes, armor and Glassbone are their own fields.",
			"rewards": "Gold is the floor's roll (FloorData) times the fight's role's gold_multiplier; whether it offers cards, and an optional basic fight's extra (a Samphire; a removal is the collector's alone), are its role's too (EncounterRewards, by BattleController.encounter_role()). Keepsake: the first member whose table drops one, a line of the reward screen's own whose CHOOSE opens its offer, left behind on WALK ON (RegionField._roll_keepsake_drop()). Armor: one worn piece from the first member with an armor_table, RARE at its armor_rare_chance, never the piece worn, lying where it fell (RegionField._drop_armor()). Glassbone: every member's, summed. Weapon: the first member's weapon_reward, a line of the reward screen's own whose CHOOSE opens its plate, TAKE or LEAVE in place of the weapon carried, left behind on WALK ON - never while it is the one carried (RewardScreen.offer_weapon()).",
			"intent_values": "ATTACK damage is per hit, before statuses, escalation shown per stage. Erratic enemies pick each turn by weight instead of looping.",
			"rarity_rates": "A floor's rarity_rates are what a normal fight's card offer rolls each slot with there: EncounterRewards.fight_rarity_by_floor's step for that floor (FightRarityTable.rates_for_floor()), else the pool's own normal rates. Relative weights, renormalised over the tiers that still have an eligible card. elite_rarity_rates are the pool's own, for a fight with an elite in it; the collector rolls at the pool's own normal rates.",
		},
		"regions": region_list,
		"enemies": roster,
	}

static func _region_entry(region: RegionData, region_index: int, appearances: Dictionary) -> Dictionary:
	var floors: Array = []
	var floor_index: int = 0
	for floor_data in region.floors:
		if floor_data != null:
			floors.append(_floor_entry(floor_data, region_index, floor_index, appearances))
		floor_index += 1
	return {
		"region": region_index + 1,
		"display_name": region.display_name,
		"file": region.resource_path,
		"floors": floors,
	}

static func _floor_entry(floor_data: FloorData, region_index: int, floor_index: int, appearances: Dictionary) -> Dictionary:
	var pool: RewardPool = floor_data.reward_pool
	var rewards: Dictionary = {
		"gold": [floor_data.gold_min, floor_data.gold_max] if pool != null else null,
		"card_pool": _path(pool),
		"cards_offered": _cards_offered() if pool != null else 0,
		"rarity_rates": _fight_rates_entry(pool, floor_index + 1) if pool != null else null,
		"elite_rarity_rates": {
			"common": pool.elite_common_rate,
			"uncommon": pool.elite_uncommon_rate,
			"rare": pool.elite_rare_rate,
			"ultra_rare": pool.elite_ultra_rare_rate,
		} if pool != null else null,
		"bundle_rare_pool": _path(floor_data.rare_pool),
	}
	var encounters: Array = []
	var gate_slot: EncounterSlot = _gate_slot(floor_data)
	for slot in floor_data.slots:
		if slot == null:
			continue
		for option in slot.options:
			if option == null:
				continue
			var encounter: Dictionary = _encounter_entry(floor_data, slot, option, slot == gate_slot)
			encounters.append(encounter)
			for entry in option.members:
				if entry == null or entry.enemy_data == null:
					continue
				var path: String = entry.enemy_data.resource_path
				var list: Array = appearances.get(path, [])
				list.append({
					"region": region_index + 1,
					"floor": floor_index + 1,
					"slot": String(slot.slot_id),
					"option": String(option.option_id),
					"cluster": encounter["cluster"],
					"required": slot.required,
					"gate_fight": encounter["gate_fight"],
				})
				appearances[path] = list
	return {
		"floor": floor_index + 1,
		"file": floor_data.resource_path,
		"rewards": rewards,
		"encounters": encounters,
	}

# RegionField._gate_slot()'s rule: the first required slot, else the first.
static func _gate_slot(floor_data: FloorData) -> EncounterSlot:
	var first: EncounterSlot = null
	for slot in floor_data.slots:
		if slot == null:
			continue
		if slot.required:
			return slot
		if first == null:
			first = slot
	return first

static func _encounter_entry(floor_data: FloorData, slot: EncounterSlot, option: EncounterOption, gate_fight: bool) -> Dictionary:
	var cluster: Variant = String(slot.slot_id) if option.members.size() > 1 else null
	var elite: bool = false
	var top_tier: bool = false
	var keepsake: Variant = null
	var armor: Variant = null
	var glassbone: int = 0
	var member_list: Array = []
	for member_index in option.members.size():
		var entry: FloorEnemy = option.members[member_index]
		if entry == null:
			continue
		var data: EnemyData = entry.enemy_data
		top_tier = top_tier or entry.card_reward == FloorEnemy.CardReward.TOP_TIER_FIRST
		if data != null:
			elite = elite or data.is_elite
			glassbone += maxi(data.glassbone_reward, 0)
			if keepsake == null and data.keepsake_table != null:
				keepsake = {"from": data.enemy_name, "table": data.keepsake_table.resource_path}
			if armor == null and data.armor_table != null:
				armor = {"from": data.enemy_name, "table": data.armor_table.resource_path}
		member_list.append(_member_entry(slot, option, member_index))
	var names: Array[String] = []
	for member: Dictionary in member_list:
		names.append(member["name"])
	var encounter: Dictionary = {
		"slot": String(slot.slot_id),
		"option": String(option.option_id),
		"weight": _num(option.weight),
		"anchor": _vec2(slot.position),
		"slot_yaw_degrees": _num(slot.yaw_degrees),
		"cluster": cluster,
		"names": " + ".join(names),
		"required": slot.required,
		"elite": elite,
		"gate_fight": gate_fight,
	}
	if gate_fight:
		encounter["gate"] = {
			"exit_kind": FloorData.ExitKind.keys()[floor_data.exit_kind],
			"exit_direction": _vec2(floor_data.exit_direction),
			"gate_distance_beyond_enemy": _num(floor_data.gate_distance_beyond_enemy),
			"bar_axis_offset": _num(floor_data.gate_bar_axis_offset),
			"channel_max_width": _num(floor_data.gate_channel_max_width),
			# FloorData.engage_line_enabled: its offset along the exit, or null when off.
			"engage_line_offset_m": _num(floor_data.engage_line_offset_m) if floor_data.engage_line_enabled else null,
		}
	encounter["elite_rewards"] = {
		"gold_multiplier": _num(_elite_gold_multiplier()) if elite else null,
		"card_rates": "top tier first" if top_tier else ("elite" if elite else "normal"),
		"why": "FloorEnemy.card_reward TOP_TIER_FIRST" if top_tier else ("an elite member" if elite else null),
	}
	encounter["patrol"] = _patrol_entry(slot, option)
	encounter["members"] = member_list
	var props: Array = []
	for prop in option.props:
		if prop != null:
			props.append({"scene": _path(prop.scene), "position": _vec2(_prop_at(slot, prop))})
	encounter["props"] = props
	encounter["keepsake_drop"] = keepsake
	encounter["armor_drop"] = armor
	encounter["glassbone"] = glassbone
	return encounter

# Where a top-level option prop stands, floor frame.
static func _prop_at(slot: EncounterSlot, prop: FloorProp) -> Vector2:
	return slot.to_floor(Vector2(prop.position.x, prop.position.z))

static func _member_entry(slot: EncounterSlot, option: EncounterOption, member_index: int) -> Dictionary:
	var entry: FloorEnemy = option.members[member_index]
	var data: EnemyData = entry.enemy_data
	var face_prop: Variant = null
	if entry.face_prop_index >= 0 and entry.face_prop_index < option.props.size():
		var prop: FloorProp = option.props[entry.face_prop_index]
		face_prop = {
			"index": entry.face_prop_index,
			"scene": _path(prop.scene) if prop != null else null,
			"position": _vec2(_prop_at(slot, prop)) if prop != null else null,
		}
	var member: Dictionary = {
		"member": member_index,
		"name": data.enemy_name if data != null else "",
		"enemy_file": _path(data),
		"hp": data.max_hp if data != null else 0,
		"anchor": entry.anchor,
		"card_reward": FloorEnemy.CardReward.keys()[entry.card_reward],
		"position": _vec2(slot.to_floor(entry.position)),
		"yaw_degrees": _num(slot.yaw_degrees + entry.yaw_degrees),
		"face_prop": face_prop,
	}
	# A rider (FloorEnemy.rides_on): on which member, and where on it -
	# its position above is its spot in the fight's line.
	if entry.rides_on >= 0:
		member["rides_on"] = {
			"member": entry.rides_on,
			"seat_offset_m": [_num(entry.ride_offset.x), _num(entry.ride_offset.y), _num(entry.ride_offset.z)],
			"yaw_degrees": _num(entry.ride_yaw_degrees),
		}
	return member

static func _patrol_entry(slot: EncounterSlot, option: EncounterOption) -> Variant:
	var patrol: FloorPatrol = option.patrol
	if patrol == null:
		return null
	var waypoints: Array = []
	for point in patrol.waypoints:
		waypoints.append(_vec2(slot.to_floor(point)))
	return {
		"waypoints": waypoints,
		"dwell_seconds": [_num(patrol.dwell_min_seconds), _num(patrol.dwell_max_seconds)],
	}

static func _enemy_entry(data: EnemyData, appears_on: Array) -> Dictionary:
	return {
		"name": data.enemy_name,
		"file": data.resource_path,
		"hp": data.max_hp,
		"elite": data.is_elite,
		"mechanic_summary": data.mechanic_summary,
		"starts_dormant": data.starts_dormant,
		"starts_aboard": data.starts_aboard,
		"field": _field_entry(data),
		"moveset": _moveset_entry(data),
		"statuses": _status_entries(data),
		"rewards": {
			"keepsake_table": _keepsake_entry(data.keepsake_table),
			"armor_table": _armor_entry(data.armor_table, data.armor_rare_chance),
			"glassbone": data.glassbone_reward,
			"weapon": data.weapon_reward.resource_path if data.weapon_reward != null else null,
			"gold_and_cards": "the floor's - see regions[].floors[].rewards",
		},
		"defeat_line": data.defeat_line,
		"sounds": _sounds_entry(data),
		"appears_on": appears_on,
	}

static func _field_entry(data: EnemyData) -> Dictionary:
	var attachment: Variant = null
	if not data.attachment_scene_path.is_empty():
		var script := _scene_root_property(data.attachment_scene_path, "script") as Script
		attachment = {
			"scene": data.attachment_scene_path,
			"class": String(script.get_global_name()) if script != null else "",
		}
	return {
		"model": data.model_scene_path if not data.model_scene_path.is_empty() else _default_model_path(),
		"model_is_default": data.model_scene_path.is_empty(),
		"model_scale": _num(data.model_scale),
		"model_yaw_offset_degrees": _num(data.model_yaw_offset_degrees),
		"attachment": attachment,
		"contact_radius_m": _num(data.contact_radius_m),
		"cluster_gap_m": _num(data.cluster_gap_m) if data.cluster_gap_m >= 0.0 else null,
		"rest_height_m": _num(data.rest_height_m),
		"sink_m": _num(data.sink_m),
		"battle_hover_m": _num(data.battle_hover_m),
		"buried_on_field": data.rest_height_m < 0.0,
		"flies_in_battle": data.battle_hover_m > 0.0,
		"harness_point": [_num(data.harness_point.x), _num(data.harness_point.y), _num(data.harness_point.z)] if data.harness_point != Vector3.ZERO else null,
	}

static func _moveset_entry(data: EnemyData) -> Dictionary:
	var intents: Array = []
	for intent in data.intents:
		if intent != null:
			intents.append(_intent_entry(data, intent))
	var escalation: Variant = null
	if not data.escalation_multipliers.is_empty():
		var stages: Array = []
		var length: int = maxi(data.escalation_stage_length, 1)
		for stage in data.escalation_multipliers.size():
			var last: bool = stage == data.escalation_multipliers.size() - 1
			var from_turn: int = stage * length + 1
			stages.append({
				"turns": ("%d+" % from_turn) if last else ("%d-%d" % [from_turn, from_turn + length - 1]),
				"multiplier": _num(data.escalation_multipliers[stage]),
			})
		escalation = {"applies_to": "ATTACK damage, rounded", "stage_length_turns": length, "stages": stages}
	var pain_turn: Variant = null
	if data.pain_turn_hp_threshold > 0.0:
		pain_turn = {
			"below_hp_fraction": _num(data.pain_turn_hp_threshold),
			"below_hp": _num(data.max_hp * data.pain_turn_hp_threshold),
			"effect": "its queued action is cancelled, once per fight",
			"line": data.pain_turn_line,
		}
	var phase: Variant = null
	if data.phase_hp_threshold > 0.0 and data.phase_status != null:
		phase = {
			"below_hp_fraction": _num(data.phase_hp_threshold),
			"below_hp": _num(data.max_hp * data.phase_hp_threshold),
			"gains": data.phase_status.id,
			"effect": "gains the status once per fight; nothing is cancelled",
		}
	return {
		"selection": "erratic (weighted pick each turn)" if data.erratic_intent_selection else "loop (in order)",
		"intents": intents,
		"modified_by": _attack_modifiers(data),
		"escalation": escalation,
		"pain_turn": pain_turn,
		"phase": phase,
	}

# The statuses it can hold that add to every hit of its ATTACKs (Hungry),
# with each attack's damage while held. The attack-card status (Roused)
# is on the intent it feeds instead - see counts_attack_cards.
static func _attack_modifiers(data: EnemyData) -> Array:
	var modifiers: Array = []
	for reached: Array in _reachable_statuses(data):
		var status: StatusData = reached[0]
		if status == data.attack_card_status or status.attack_damage_bonus == 0:
			continue
		var attacks: Dictionary = {}
		for intent in data.intents:
			if intent != null and intent.type == EnemyIntent.IntentType.ATTACK:
				var damage: int = intent.value + status.attack_damage_bonus
				attacks[intent.intent_name] = ("%d x %d" % [damage, intent.hits]) if intent.hits > 1 else str(damage)
		modifiers.append({
			"status": status.id,
			"per_hit_bonus": status.attack_damage_bonus,
			"only_while_critical": status.bonus_requires_critical,
			"attacks_while_held": attacks,
		})
	return modifiers

static func _intent_entry(data: EnemyData, intent: EnemyIntent) -> Dictionary:
	var entry: Dictionary = {
		"name": intent.intent_name,
		"type": EnemyIntent.IntentType.keys()[intent.type],
	}
	match intent.type:
		EnemyIntent.IntentType.ATTACK:
			entry["damage_per_hit"] = intent.value
			entry["hits"] = intent.hits
			if intent.lands_as_strike_back:
				entry["lands_as_strike_back"] = "the statuses that wait for its own turn (Braced, Garnished, No Further, Unbroken) don't reduce it; Block does"
			# A multi-hit attack gains what its phase adds (StatusData.
			# bonus_hits - EnemyTurn.hit_count()).
			if intent.hits > 1 and data.phase_status != null and data.phase_status.bonus_hits > 0:
				entry["hits_after_phase"] = intent.hits + data.phase_status.bonus_hits
			if not data.escalation_multipliers.is_empty():
				var by_stage: Array = []
				for multiplier in data.escalation_multipliers:
					by_stage.append(roundi(float(intent.value) * multiplier))
				entry["damage_per_hit_by_stage"] = by_stage
		EnemyIntent.IntentType.DEFEND:
			entry["block"] = intent.value
		EnemyIntent.IntentType.HEAL_ALLY:
			entry["heal_each_packmate"] = intent.value
		EnemyIntent.IntentType.SIGNAL:
			entry["signal"] = "deploys every packmate still aboard and wakes every dormant one; each living packmate answers at once with one attack out of turn"
		EnemyIntent.IntentType.DIG:
			# Its moves under the sand, one a turn, the last surfacing it;
			# its mounds, each a target of mound_hp.
			var under: Array = []
			for move: EnemyIntent in intent.under_moves:
				if move != null:
					under.append(_intent_entry(data, move))
			entry["dig"] = {
				"mounds": intent.mound_count,
				"mound_hp": intent.mound_hp,
				"under_moves": under,
				"found_status": intent.found_status.id if intent.found_status != null else null,
			}
	if data.erratic_intent_selection:
		entry["erratic_weight"] = _num(intent.erratic_weight)
		entry["turn_one_locked"] = intent.turn_one_locked
		entry["no_immediate_repeat"] = intent.no_immediate_repeat
	if intent.simultaneous:
		entry["simultaneous"] = "a shared beat: every living member queued on one acts at once"
	if intent.pack_only:
		entry["pack_only"] = "a pack move: dropped from the loop once the enemy is the last of its pack"
	if intent.interrupt_threshold > 0:
		entry["interrupt"] = {
			"break_threshold": intent.interrupt_threshold,
			"on_interrupt": _intent_entry(data, intent.on_interrupt) if intent.on_interrupt != null else null,
			"clears_attack_card_status": intent.counts_attack_cards and data.attack_card_status != null,
		}
	if intent.rear_while_queued:
		entry["rears_while_queued"] = true
	if intent.status_while_queued != null:
		entry["status_while_queued"] = intent.status_while_queued.id
	if intent.status_on_resolve != null:
		entry["status_on_resolve"] = intent.status_on_resolve.id
	if intent.counts_attack_cards and data.attack_card_status != null:
		var status: StatusData = data.attack_card_status
		entry["counts_attack_cards"] = {
			"status": status.id,
			"bonus_per_card": status.attack_damage_bonus,
			"max_stacks": status.max_stacks,
			"damage_range": [intent.value, intent.value + status.attack_damage_bonus * status.max_stacks] if status.max_stacks > 0 else null,
		}
	if intent.applies_to_player != null and intent.applied_amount > 0:
		entry["applies_to_player"] = {"status": intent.applies_to_player.id, "amount": intent.applied_amount}
	return entry

# Every status the enemy starts with or can gain, each once, with how it
# comes and its text resolved at one stack.
static func _status_entries(data: EnemyData) -> Array:
	var entries: Array = []
	for reached: Array in _reachable_statuses(data):
		var status: StatusData = reached[0]
		var entry: Dictionary = {
			"id": status.id,
			"name": status.display_name,
			"file": status.resource_path,
			"gained": reached[1],
			"description": status.description,
			"text": Status.new(status).describe(),
			"fields": _status_fields(status),
		}
		if data.status_gained_sound != null and data.status_gained_sound_on == status:
			entry["gained_sound"] = data.status_gained_sound.resource_path
		entries.append(entry)
	return entries

# [StatusData, how it comes] for each status the enemy can hold, once, in
# the order it meets them: its starting statuses, the ones its intents
# hold while queued or bring when they resolve, its attack-card status, and
# whatever those turn into (grants_when_alone / grants_on_critical /
# grants_on_turn_start) - and what its attacks put on the player (EnemyIntent.
# applies_to_player).
static func _reachable_statuses(data: EnemyData) -> Array:
	var queue: Array = []
	for status in data.starting_statuses:
		if status != null:
			queue.append([status, "starts every fight with it"])
	for intent in data.intents:
		if intent != null and intent.status_while_queued != null:
			queue.append([intent.status_while_queued, "while its %s is queued" % intent.intent_name])
	for intent in data.intents:
		if intent != null and intent.status_on_resolve != null:
			queue.append([intent.status_on_resolve, "from its %s resolving until its next move" % intent.intent_name])
	for intent in data.intents:
		if intent != null and intent.type == EnemyIntent.IntentType.DIG and intent.found_status != null:
			queue.append([intent.found_status, "its own mound broken under its %s, for %d of its turns" % [intent.intent_name, intent.found_status.default_duration_turns]])
	for intent in data.intents:
		if intent != null and intent.applies_to_player != null and intent.applied_amount > 0:
			queue.append([intent.applies_to_player, "put on the player by its %s, %d at a time" % [intent.intent_name, intent.applied_amount]])
	if data.attack_card_status != null:
		var while_queued: Array[String] = []
		for intent in data.intents:
			if intent != null and intent.counts_attack_cards:
				while_queued.append(intent.intent_name)
		queue.append([data.attack_card_status, "a stack per Attack card played against it while %s is queued" % " / ".join(while_queued)])
	if data.phase_status != null and data.phase_hp_threshold > 0.0:
		queue.append([data.phase_status, "once, the first time its HP is below %s of %d" % [str(_num(data.phase_hp_threshold)), data.max_hp]])
	if data.turn_end_status != null and data.turn_end_status_stacks > 0:
		queue.append([data.turn_end_status, "%d stack(s) at the end of each turn it acts, kept for the fight" % data.turn_end_status_stacks])
	var reached: Array = []
	var seen: Array[String] = []
	while not queue.is_empty():
		var next: Array = queue.pop_front()
		var status: StatusData = next[0]
		if seen.has(status.resource_path):
			continue
		seen.append(status.resource_path)
		reached.append(next)
		if status.grants_when_alone != null:
			queue.append([status.grants_when_alone, "from %s, when no packmate is left living" % status.display_name])
		if status.grants_on_critical != null:
			queue.append([status.grants_on_critical, "from %s, once its holder is Critical" % status.display_name])
		if status.grants_on_turn_start != null:
			queue.append([status.grants_on_turn_start, "from %s, at the next turn's start" % status.display_name])
	return reached

# The StatusData fields that differ from the script's defaults, enums by
# name and statuses by id - whatever rule the status carries, without a
# hand-kept list of which fields matter.
static func _status_fields(status: StatusData) -> Dictionary:
	var fields: Dictionary = {}
	var script: Script = status.get_script()
	for property in status.get_property_list():
		var name: String = property["name"]
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or STATUS_SKIP.has(name):
			continue
		var value: Variant = status.get(name)
		var default: Variant = script.get_property_default_value(name)
		if typeof(value) == typeof(default) and value == default:
			continue
		match name:
			"category":
				value = StatusData.Category.keys()[int(value)]
			"stack_rule":
				value = StatusData.StackRule.keys()[int(value)]
			"modifier_target":
				value = StatusData.ModifierTarget.keys()[int(value)]
			"mark":
				value = StatusData.Mark.keys()[int(value)]
			"modifier_operation":
				value = StatusData.ModifierOperation.keys()[int(value)]
			"default_duration_turns":
				if int(value) == StatusData.DURATION_UNTIL_REMOVED:
					value = "until removed"
				elif int(value) == StatusData.DURATION_UNTIL_TRIGGERED:
					value = "until triggered"
		if value is StatusData:
			value = (value as StatusData).id
		elif value is float:
			value = _num(value)
		fields[name] = value
	return fields

# An armor table (EnemyData.armor_table): its pieces by rarity, drawn RARE
# at rare_chance (KeepsakeTable.roll_by_rarity()) - one always left.
static func _armor_entry(table: KeepsakeTable, rare_chance: float) -> Variant:
	if table == null:
		return null
	var entries: Array = []
	for entry in table.entries:
		if entry == null or entry.trinket == null:
			continue
		entries.append({
			"piece": entry.trinket.display_name,
			"id": String(entry.trinket.id),
			"file": entry.trinket.resource_path,
			"rarity": CardData.CardRarity.keys()[entry.trinket.rarity],
			"weight": _num(entry.weight),
		})
	return {
		"file": table.resource_path,
		"rare_chance": _num(rare_chance),
		"entries": entries,
	}

static func _keepsake_entry(table: KeepsakeTable) -> Variant:
	if table == null:
		return null
	var entries: Array = []
	for entry in table.entries:
		if entry == null or entry.trinket == null:
			continue
		entries.append({
			"keepsake": entry.trinket.display_name,
			"id": String(entry.trinket.id),
			"file": entry.trinket.resource_path,
			"weight": _num(entry.weight),
			"unique_per_run": entry.unique_per_run,
		})
	return {
		"file": table.resource_path,
		"guaranteed": table.guaranteed,
		"drop_chance": _num(table.drop_chance) if not table.guaranteed else 1.0,
		"entries": entries,
	}

static func _sounds_entry(data: EnemyData) -> Dictionary:
	var attachment: Dictionary = {}
	if not data.attachment_scene_path.is_empty():
		attachment = _scene_sounds(data.attachment_scene_path)
	return {
		"contact": _stream_paths(data.contact_sounds),
		"armored_contact": _stream_paths(data.armored_contact_sounds),
		"pitch_jitter": _num(data.pitch_jitter),
		"pain_turn": _path(data.pain_turn_sound),
		"status_gained": {"on": data.status_gained_sound_on.id, "sound": _path(data.status_gained_sound)} if data.status_gained_sound_on != null and data.status_gained_sound != null else null,
		"attachment": attachment,
	}

static func _stream_paths(streams: Array[AudioStream]) -> Array:
	var paths: Array = []
	for stream in streams:
		if stream != null:
			paths.append(stream.resource_path)
	return paths

# Every AudioStream a scene's nodes are set to, "node.property": path -
# the sounds an attachment carries itself (the Blackback's clatter).
static func _scene_sounds(scene_path: String) -> Dictionary:
	var sounds: Dictionary = {}
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return sounds
	var state: SceneState = scene.get_state()
	for node in state.get_node_count():
		for property in state.get_node_property_count(node):
			var value: Variant = state.get_node_property_value(node, property)
			if value is AudioStream:
				var key: String = "%s.%s" % [state.get_node_name(node), state.get_node_property_name(node, property)]
				sounds[key] = (value as AudioStream).resource_path
	return sounds

# FieldEnemy's own body for an EnemyData that names none - read off the
# script at run time: naming FieldEnemy here would compile the field (and
# its autoloads) before a -s script has them.
static func _default_model_path() -> String:
	var script := load(FIELD_ENEMY_SCRIPT_PATH) as Script
	if script == null:
		return ""
	return String(script.get_script_constant_map().get("DEFAULT_MODEL_SCENE_PATH", ""))

# The EncounterRewards RegionField's scene points at, or null.
static func _encounter_rewards() -> EncounterRewards:
	var path: Variant = _scene_root_property(REGION_SCENE_PATH, "encounter_rewards_path")
	return load(String(path)) as EncounterRewards if path != null else null

# The elite role's gold multiplier: EncounterRewards.elite, from the
# rewards RegionField's scene points at.
static func _elite_gold_multiplier() -> float:
	var rewards: EncounterRewards = _encounter_rewards()
	if rewards == null or rewards.elite == null:
		return 1.0
	return rewards.elite.gold_multiplier

# A normal fight's rarity rates on the region's `floor_number` (1 = its
# first): the floor table's step for it (RegionField._fight_rarity_
# rates()), else `pool`'s own normal rates.
static func _fight_rates_entry(pool: RewardPool, floor_number: int) -> Dictionary:
	var rewards: EncounterRewards = _encounter_rewards()
	var rates: RarityRates = rewards.fight_rarity_by_floor.rates_for_floor(floor_number) if rewards != null and rewards.fight_rarity_by_floor != null else null
	if rates != null:
		return {
			"common": rates.common_rate,
			"uncommon": rates.uncommon_rate,
			"rare": rates.rare_rate,
			"ultra_rare": rates.ultra_rare_rate,
		}
	return {
		"common": pool.common_rate,
		"uncommon": pool.uncommon_rate,
		"rare": pool.rare_rate,
		"ultra_rare": pool.ultra_rare_rate,
	}

static func _cards_offered() -> int:
	var value: Variant = _scene_root_property(REWARD_SCREEN_SCENE_PATH, "choice_count")
	return int(value) if value != null else 0

# A scene's root property as the scene sets it, else its root script's
# default. Read off the SceneState - nothing is instantiated.
static func _scene_root_property(scene_path: String, property_name: String) -> Variant:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var state: SceneState = scene.get_state()
	var script: Script = null
	for property in state.get_node_property_count(0):
		var name: StringName = state.get_node_property_name(0, property)
		if name == StringName(property_name):
			return state.get_node_property_value(0, property)
		if name == &"script":
			script = state.get_node_property_value(0, property) as Script
	if script != null:
		return script.get_property_default_value(property_name)
	return null

static func _enemy_paths() -> Array[String]:
	var paths: Array[String] = []
	for file_name in DirAccess.get_files_at(ENEMY_DIR):
		if file_name.ends_with(".tres"):
			paths.append(ENEMY_DIR + file_name)
	paths.sort()
	return paths

static func _path(resource: Resource) -> Variant:
	return resource.resource_path if resource != null else null

static func _vec2(value: Vector2) -> Array:
	return [_num(value.x), _num(value.y)]

# Floats to 4 places, so a float32 position (17.6 stored as 17.6000003)
# writes as authored.
static func _num(value: float) -> float:
	return snappedf(value, 0.0001)
