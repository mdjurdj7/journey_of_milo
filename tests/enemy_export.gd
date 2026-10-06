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

const OUTPUT_PATH := "res://docs/enemy_export.json"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const REWARD_SCREEN_SCENE_PATH := "res://battle/reward_screen.tscn"
const ENEMY_DIR := "res://battle/rules/enemies/"
const FIELD_ENEMY_SCRIPT_PATH := "res://field/field_enemy.gd"
const REGENERATE := "Godot_v4.7.1.exe --headless --path . -s res://tests/enemy_export.gd"
# StatusData fields the export never lists as numbers: names and prose,
# shown elsewhere in the entry, and its presentation.
const STATUS_SKIP: Array[String] = ["id", "display_name", "description", "battle_animation", "script", "resource_local_to_scene", "resource_path", "resource_name", "resource_scene_unique_id"]

func _initialize() -> void:
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		print("enemy_export: could not write %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(to_json())
	file.close()
	print("enemy_export: wrote %s" % OUTPUT_PATH)
	quit(0)

static func to_json() -> String:
	return JSON.stringify(build(), "  ", false) + "\n"

# The regions RegionField plays: its scene's own `region` export (one
# region today).
static func regions() -> Array[RegionData]:
	var found: Array[RegionData] = []
	var region := _scene_root_property(REGION_SCENE_PATH, "region") as RegionData
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
				REGION_SCENE_PATH + " (its region and elite_gold_multiplier)",
				"res://floors/*.tres (RegionData, FloorData, FloorEnemy, FloorPatrol, FloorProp)",
				ENEMY_DIR + "*.tres (EnemyData, EnemyIntent)",
				"res://battle/rules/statuses/*.tres (StatusData, resolved through Status.describe())",
				"res://run/keepsakes/*.tres (KeepsakeTable, TrinketData)",
				"res://cards/pools/*.tres (RewardPool rarity rates)",
				REWARD_SCREEN_SCENE_PATH + " (choice_count)",
			],
			"positions": "World XZ offsets from the floor's spawn, metres ([x, z]).",
			"required": "FloorEnemy.required: the floor is cleared, and its gate opens, once no required enemy stands. A cluster is the entries sharing a FloorEnemy.group; it is required when any member is.",
			"gate_fight": "The encounter holding FloorData.enemies[0]: RegionField._setup_exit_gate() places the gate gate_distance_beyond_enemy past that enemy, along exit_direction.",
			"elite": "EnemyData.is_elite. A fight with an elite in it pays the floor's gold times RegionField.elite_gold_multiplier (rounded) and rolls its card at the pool's elite rarity rates. A placement marked FloorEnemy.card_reward TOP_TIER_FIRST (floor 5's region-end Greyshelf) offers its cards from the highest tier down instead (RewardPool.roll_top_tier()), at the floor's gold. See each encounter's elite_rewards. Keepsakes and Glassbone are their own fields.",
			"rewards": "Gold and the card reward are the floor's (FloorData), the same for every fight on it. Keepsake: the first member whose table drops one (RegionField._roll_keepsake_drop()). Glassbone: every member's, summed.",
			"intent_values": "ATTACK damage is per hit, before statuses, escalation shown per stage. Erratic enemies pick each turn by weight instead of looping.",
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
		"rarity_rates": {
			"common": pool.common_rate,
			"uncommon": pool.uncommon_rate,
			"rare": pool.rare_rate,
			"ultra_rare": pool.ultra_rare_rate,
		} if pool != null else null,
		"elite_rarity_rates": {
			"common": pool.elite_common_rate,
			"uncommon": pool.elite_uncommon_rate,
			"rare": pool.elite_rare_rate,
			"ultra_rare": pool.elite_ultra_rare_rate,
		} if pool != null else null,
		"bundle_rare_pool": _path(floor_data.rare_pool),
	}
	var encounters: Array = []
	for members in _clusters(floor_data):
		var encounter: Dictionary = _encounter_entry(floor_data, members)
		encounters.append(encounter)
		for index: int in members:
			var data: EnemyData = floor_data.enemies[index].enemy_data
			if data == null:
				continue
			var list: Array = appearances.get(data.resource_path, [])
			list.append({
				"region": region_index + 1,
				"floor": floor_index + 1,
				"cluster": encounter["cluster"],
				"required": floor_data.enemies[index].required,
				"gate_fight": encounter["gate_fight"],
			})
			appearances[data.resource_path] = list
	return {
		"floor": floor_index + 1,
		"file": floor_data.resource_path,
		"rewards": rewards,
		"encounters": encounters,
	}

# FloorData.enemies grouped into fights, in the order each fight's first
# entry is listed: one cluster per non-empty group, every other entry on
# its own. Indices into FloorData.enemies.
static func _clusters(floor_data: FloorData) -> Array:
	var clusters: Array = []
	var by_group: Dictionary = {}
	for index in floor_data.enemies.size():
		var entry: FloorEnemy = floor_data.enemies[index]
		if entry == null:
			continue
		if entry.group == &"":
			clusters.append([index])
		elif by_group.has(entry.group):
			var members: Array = by_group[entry.group]
			members.append(index)
		else:
			var members: Array = [index]
			by_group[entry.group] = members
			clusters.append(members)
	return clusters

static func _encounter_entry(floor_data: FloorData, members: Array) -> Dictionary:
	var first: FloorEnemy = floor_data.enemies[members[0]]
	var cluster: Variant = String(first.group) if first.group != &"" else null
	var required: bool = false
	var elite: bool = false
	var top_tier: bool = false
	var gate_fight: bool = false
	var keepsake: Variant = null
	var glassbone: int = 0
	var member_list: Array = []
	for index: int in members:
		var entry: FloorEnemy = floor_data.enemies[index]
		var data: EnemyData = entry.enemy_data
		required = required or entry.required
		top_tier = top_tier or entry.card_reward == FloorEnemy.CardReward.TOP_TIER_FIRST
		gate_fight = gate_fight or index == 0
		if data != null:
			elite = elite or data.is_elite
			glassbone += maxi(data.glassbone_reward, 0)
			if keepsake == null and data.keepsake_table != null:
				keepsake = {"from": data.enemy_name, "table": data.keepsake_table.resource_path}
		member_list.append(_member_entry(floor_data, index))
	var names: Array[String] = []
	for member: Dictionary in member_list:
		names.append(member["name"])
	var encounter: Dictionary = {
		"cluster": cluster,
		"names": " + ".join(names),
		"required": required,
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
		}
	encounter["elite_rewards"] = {
		"gold_multiplier": _num(_elite_gold_multiplier()) if elite else null,
		"card_rates": "top tier first" if top_tier else ("elite" if elite else "normal"),
		"why": "FloorEnemy.card_reward TOP_TIER_FIRST" if top_tier else ("an elite member" if elite else null),
	}
	encounter["patrol"] = _patrol_entry(floor_data, first.group)
	encounter["members"] = member_list
	encounter["keepsake_drop"] = keepsake
	encounter["glassbone"] = glassbone
	return encounter

static func _member_entry(floor_data: FloorData, index: int) -> Dictionary:
	var entry: FloorEnemy = floor_data.enemies[index]
	var data: EnemyData = entry.enemy_data
	var face_prop: Variant = null
	if entry.face_prop_index >= 0 and entry.face_prop_index < floor_data.props.size():
		var prop: FloorProp = floor_data.props[entry.face_prop_index]
		face_prop = {
			"index": entry.face_prop_index,
			"scene": _path(prop.scene) if prop != null else null,
			"position": _vec3_xz(prop.position) if prop != null else null,
		}
	return {
		"index": index,
		"name": data.enemy_name if data != null else "",
		"enemy_file": _path(data),
		"hp": data.max_hp if data != null else 0,
		"required": entry.required,
		"anchor": entry.anchor,
		"card_reward": FloorEnemy.CardReward.keys()[entry.card_reward],
		"position": _vec2(entry.position),
		"yaw_degrees": _num(entry.yaw_degrees),
		"face_prop": face_prop,
	}

static func _patrol_entry(floor_data: FloorData, group: StringName) -> Variant:
	if group == &"":
		return null
	for patrol in floor_data.patrols:
		if patrol != null and patrol.group == group:
			var waypoints: Array = []
			for point in patrol.waypoints:
				waypoints.append(_vec2(point))
			return {
				"waypoints": waypoints,
				"dwell_seconds": [_num(patrol.dwell_min_seconds), _num(patrol.dwell_max_seconds)],
			}
	return null

static func _enemy_entry(data: EnemyData, appears_on: Array) -> Dictionary:
	return {
		"name": data.enemy_name,
		"file": data.resource_path,
		"hp": data.max_hp,
		"elite": data.is_elite,
		"mechanic_summary": data.mechanic_summary,
		"field": _field_entry(data),
		"moveset": _moveset_entry(data),
		"statuses": _status_entries(data),
		"rewards": {
			"keepsake_table": _keepsake_entry(data.keepsake_table),
			"glassbone": data.glassbone_reward,
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
	if data.erratic_intent_selection:
		entry["erratic_weight"] = _num(intent.erratic_weight)
		entry["turn_one_locked"] = intent.turn_one_locked
		entry["no_immediate_repeat"] = intent.no_immediate_repeat
	if intent.simultaneous:
		entry["simultaneous"] = "a pack move: every living member queued on one acts in the same beat"
	if intent.interrupt_threshold > 0:
		entry["interrupt"] = {
			"break_threshold": intent.interrupt_threshold,
			"on_interrupt": _intent_entry(data, intent.on_interrupt) if intent.on_interrupt != null else null,
			"stuns_with": data.stun_status.id if intent.deny_next_on_interrupt and data.stun_status != null else null,
			"clears_attack_card_status": intent.counts_attack_cards and data.attack_card_status != null,
		}
	if intent.rear_while_queued:
		entry["rears_while_queued"] = true
	if intent.counts_attack_cards and data.attack_card_status != null:
		var status: StatusData = data.attack_card_status
		entry["counts_attack_cards"] = {
			"status": status.id,
			"bonus_per_card": status.attack_damage_bonus,
			"max_stacks": status.max_stacks,
			"damage_range": [intent.value, intent.value + status.attack_damage_bonus * status.max_stacks] if status.max_stacks > 0 else null,
		}
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
# the order it meets them: its starting statuses, its attack-card status,
# and whatever those turn into (grants_when_alone / grants_on_critical /
# grants_on_turn_start).
static func _reachable_statuses(data: EnemyData) -> Array:
	var queue: Array = []
	for status in data.starting_statuses:
		if status != null:
			queue.append([status, "starts every fight with it"])
	if data.attack_card_status != null:
		var while_queued: Array[String] = []
		for intent in data.intents:
			if intent != null and intent.counts_attack_cards:
				while_queued.append(intent.intent_name)
		queue.append([data.attack_card_status, "a stack per Attack card played against it while %s is queued" % " / ".join(while_queued)])
	if data.stun_status != null:
		var stunning: Array[String] = []
		for intent in data.intents:
			if intent != null and intent.deny_next_on_interrupt:
				stunning.append(intent.intent_name)
		queue.append([data.stun_status, "when its %s is broken" % " / ".join(stunning)])
	if data.phase_status != null and data.phase_hp_threshold > 0.0:
		queue.append([data.phase_status, "once, the first time its HP is below %s of %d" % [str(_num(data.phase_hp_threshold)), data.max_hp]])
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

# RegionField's elite_gold_multiplier, as its scene sets it.
static func _elite_gold_multiplier() -> float:
	var value: Variant = _scene_root_property(REGION_SCENE_PATH, "elite_gold_multiplier")
	return float(value) if value != null else 1.0

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

static func _vec3_xz(value: Vector3) -> Array:
	return [_num(value.x), _num(value.z)]

# Floats to 4 places, so a float32 position (17.6 stored as 17.6000003)
# writes as authored.
static func _num(value: float) -> float:
	return snappedf(value, 0.0001)
