extends RefCounted
class_name EnemyTurn

# Intent selection and execution for one enemy - fixed cycle by default,
# or a weighted erratic pick honoring no_immediate_repeat/turn_one_locked,
# ported as-is from the old project (see Phase 1 report). Pure functions
# over a Combatant + its EnemyData; battle_controller.gd calls these and
# turns the results into signals.

# Called once, at spawn - the enemy's very first queued intent.
static func pick_initial_intent(combatant: Combatant, data: EnemyData) -> void:
	if data.intents.is_empty():
		return
	if data.erratic_intent_selection:
		combatant.current_intent_index = _pick_erratic_initial_index(data)
	else:
		combatant.current_intent_index = 0

static func current_intent(combatant: Combatant, data: EnemyData) -> EnemyIntent:
	if data.intents.is_empty() or combatant.current_intent_index < 0:
		return null
	return data.intents[combatant.current_intent_index]

# One enemy's whole turn: tick its own statuses, resolve its queued
# intent, remove expired statuses, advance to the next one - mirrors the
# old project's tick-then-resolve-then-expire order exactly (Phase 1
# report), so a duration-1 status still affects the very turn that ticks
# it to 0.
static func take_turn(combatant: Combatant, data: EnemyData, player: Combatant) -> Dictionary:
	var result: Dictionary = {"attacked": false, "damage_to_hp": 0, "defended": false, "block_gained": 0}

	Status.tick_all(combatant.statuses, func(amount: int) -> void:
		combatant.hp = max(combatant.hp - amount, 0)
	)

	if combatant.hp <= 0 or data.intents.is_empty():
		return result

	var intent := current_intent(combatant, data)
	if intent != null:
		match intent.type:
			EnemyIntent.IntentType.ATTACK:
				var amount: int = Status.apply_modifiers(intent.value, combatant.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
				amount = Status.apply_modifiers(amount, player.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
				# Braced/Unflinching-shaped statuses are consumed by this
				# attack whether or not damage actually reaches HP - see
				# status.gd's consume_triggered() and StatusData.clears_on_
				# trigger's own doc.
				Status.consume_triggered(player.statuses)
				var damage_result := DamagePipeline.resolve(amount, player)
				result["attacked"] = true
				result["damage_to_hp"] = damage_result["damage_to_hp"]
				if damage_result["damage_to_hp"] > 0:
					player.rally_pool += damage_result["damage_to_hp"]
					player.took_damage_this_turn = true
			EnemyIntent.IntentType.DEFEND:
				combatant.block += intent.value
				result["defended"] = true
				result["block_gained"] = intent.value

	Status.remove_expired(combatant.statuses)
	if combatant.hp > 0:
		_advance_intent(combatant, data)
	return result

static func _advance_intent(combatant: Combatant, data: EnemyData) -> void:
	if data.intents.is_empty():
		return
	if data.erratic_intent_selection:
		combatant.current_intent_index = _pick_erratic_intent_index(data, combatant.current_intent_index)
	else:
		combatant.current_intent_index = (combatant.current_intent_index + 1) % data.intents.size()

static func _pick_erratic_intent_index(data: EnemyData, previous_index: int) -> int:
	var weights: Dictionary = {}
	for i in data.intents.size():
		var intent := data.intents[i]
		if i == previous_index and intent.no_immediate_repeat:
			continue
		weights[i] = intent.erratic_weight
	return _weighted_pick(weights, previous_index)

# The very first intent an erratic enemy ever shows - also excludes
# turn_one_locked intents (the Sputter's own Scissor/Block), so a fresh
# fight can never open on one of those.
static func _pick_erratic_initial_index(data: EnemyData) -> int:
	var weights: Dictionary = {}
	for i in data.intents.size():
		if data.intents[i].turn_one_locked:
			continue
		weights[i] = data.intents[i].erratic_weight
	return _weighted_pick(weights, 0)

# Same "weight = odds" pick the old project's weighted_random.gd
# implements - re-derived here rather than shared, since that script
# isn't ported this pass and this is the only consumer.
static func _weighted_pick(weights: Dictionary, fallback: int) -> int:
	if weights.is_empty():
		return fallback
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := randf() * total
	var cumulative := 0.0
	for key in weights:
		cumulative += weights[key]
		if roll < cumulative:
			return key
	return weights.keys().back()
