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
	_sync_buried(combatant, data)

# The queued intent: an interjection (an interrupted intent's on_
# interrupt) when one is waiting, else the loop's own.
static func current_intent(combatant: Combatant, data: EnemyData) -> EnemyIntent:
	if combatant.interjected_intent != null:
		return combatant.interjected_intent
	if data.intents.is_empty() or combatant.current_intent_index < 0:
		return null
	return data.intents[combatant.current_intent_index]

# Whether the queued intent's interrupt threshold has been met by what
# the player has dealt this turn - the attack won't land.
static func is_interrupted(combatant: Combatant, intent: EnemyIntent) -> bool:
	if intent == null or intent.type != EnemyIntent.IntentType.ATTACK or intent.interrupt_threshold <= 0:
		return false
	return combatant.damage_taken_this_turn >= intent.interrupt_threshold

# One enemy's whole turn: tick its own statuses, resolve its queued
# intent, remove expired statuses, advance to the next one - mirrors the
# old project's tick-then-resolve-then-expire order exactly (Phase 1
# report), so a duration-1 status still affects the very turn that ticks
# it to 0.
#
# An intent whose interrupt_threshold the player met this turn doesn't
# resolve: "interrupted" is true, the loop moves on as if it had, and its
# on_interrupt is queued in front of the loop for the next turn -
# "buried" in the result when that is a BURROW. A BURROW resolving does
# nothing and ends the burial: "surfaced".
static func take_turn(combatant: Combatant, data: EnemyData, player: Combatant) -> Dictionary:
	var result: Dictionary = {"attacked": false, "damage_to_hp": 0, "defended": false, "block_gained": 0, "grace_opened": 0, "interrupted": false, "buried": false, "surfaced": false}

	Status.tick_all(combatant.statuses, func(amount: int) -> void:
		combatant.hp = max(combatant.hp - amount, 0)
	)

	if combatant.hp <= 0 or data.intents.is_empty():
		return result

	var intent := current_intent(combatant, data)
	var interjected: bool = combatant.interjected_intent != null
	if is_interrupted(combatant, intent):
		result["interrupted"] = true
	elif intent != null:
		match intent.type:
			EnemyIntent.IntentType.ATTACK:
				# One pass per hit (EnemyIntent.hits, 1 for every enemy so far):
				# modifiers are re-read each hit, so a Braced/Unflinching-shaped
				# status - consumed by the first hit whether or not damage
				# reached HP, see status.gd's consume_triggered() and
				# StatusData.clears_on_trigger's own doc - only softens the
				# first; block/absorb are worn down hit by hit.
				result["attacked"] = true
				var total_to_hp: int = 0
				# Tracked per hit as well as summed, because Grace's
				# LARGEST_HIT cap is about one hit, not the turn's total -
				# and DamagePipeline is the only thing that knows the split
				# between what block ate and what reached HP.
				var largest_hit: int = 0
				for _hit in maxi(intent.hits, 1):
					var amount: int = Status.apply_modifiers(intent.value, combatant.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
					amount = Status.apply_modifiers(amount, player.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
					Status.consume_triggered(player.statuses)
					var damage_result := DamagePipeline.resolve(amount, player)
					var to_hp: int = damage_result["damage_to_hp"]
					total_to_hp += to_hp
					largest_hit = maxi(largest_hit, to_hp)
				result["damage_to_hp"] = total_to_hp
				if total_to_hp > 0:
					player.took_damage_this_turn = true
					result["grace_opened"] = open_grace(player, largest_hit, total_to_hp)
			EnemyIntent.IntentType.DEFEND:
				combatant.block += intent.value
				result["defended"] = true
				result["block_gained"] = intent.value
			EnemyIntent.IntentType.BURROW:
				result["surfaced"] = true

	Status.remove_expired(combatant.statuses)
	if combatant.hp > 0:
		# An interjection resolved leaves the loop where it was - the loop
		# already moved past the intent it replaced.
		if interjected:
			combatant.interjected_intent = null
		else:
			_advance_intent(combatant, data)
		if result["interrupted"]:
			combatant.interjected_intent = intent.on_interrupt
		_sync_buried(combatant, data)
		result["buried"] = combatant.buried
	return result

# What the queued intent WILL do if it resolves now, for the intent
# display - the exact arithmetic take_turn() runs, on copies, mutating
# nothing: the same two apply_modifiers() calls per hit, the one-shot
# statuses consumed after the first hit (on a duplicate of the player's
# status list - the Status objects themselves aren't touched), and the
# block/absorb wear-down of DamagePipeline.resolve() replayed on local
# counters. Keys: "type" (EnemyIntent.IntentType), "hits", "per_hit"
# (the first hit's modified damage - what "N x M" shows - or the block
# gained for DEFEND), "damage_to_hp" (total that would reach HP through
# block and absorb), "lethal" (damage_to_hp >= the player's current HP).
# Empty when the enemy has no intent.
#
# An ATTACK with an interrupt_threshold also carries "threshold" (the
# authored number), "threshold_left" (what the player still has to deal
# this turn, down to 0) and "interrupted" (it's been met - the attack
# won't land, so never lethal).
static func preview_intent(combatant: Combatant, data: EnemyData, player: Combatant) -> Dictionary:
	var intent := current_intent(combatant, data)
	if intent == null:
		return {}
	var preview: Dictionary = {"type": intent.type, "hits": 1, "per_hit": intent.value, "damage_to_hp": 0, "lethal": false}
	if intent.type != EnemyIntent.IntentType.ATTACK:
		return preview
	if intent.interrupt_threshold > 0:
		preview["threshold"] = intent.interrupt_threshold
		preview["threshold_left"] = maxi(intent.interrupt_threshold - combatant.damage_taken_this_turn, 0)
		preview["interrupted"] = is_interrupted(combatant, intent)
	var player_statuses: Array[Status] = player.statuses.duplicate()
	var block: int = player.block
	var absorb: int = player.absorb
	var total_to_hp: int = 0
	var hits: int = maxi(intent.hits, 1)
	for hit in hits:
		var amount: int = Status.apply_modifiers(intent.value, combatant.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
		amount = Status.apply_modifiers(amount, player_statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
		if hit == 0:
			preview["per_hit"] = amount
		Status.consume_triggered(player_statuses)
		var blocked: int = mini(block, amount)
		var after_block: int = amount - blocked
		var absorbed: int = mini(absorb, after_block)
		block -= blocked
		absorb -= absorbed
		total_to_hp += after_block - absorbed
	preview["hits"] = hits
	preview["damage_to_hp"] = total_to_hp
	preview["lethal"] = total_to_hp >= player.hp and not bool(preview.get("interrupted", false))
	return preview

# Unblocked damage becomes Grace. Accumulates ACROSS the whole enemy
# turn rather than per enemy: the cap is the window's, so two enemies
# hitting for 5 and 8 leave 8 under LARGEST_HIT and 13 under SUM. Called
# by take_turn() and never by anything else; public only so
# battle_controller.gd's tests of the same rule have a seam.
#
# Only reached when damage actually got past block and absorb, and never
# from DamagePipeline.apply_bypass() - which is the whole of self-damage
# and status ticks - so a Bite Down opens nothing without being
# special-cased. Returns how much Grace this call added.
static func open_grace(player: Combatant, largest_hit: int, total_to_hp: int) -> int:
	if not player.has_grace:
		return 0
	var before: int = player.grace
	if player.grace_cap_mode == CharacterData.GraceCapMode.SUM:
		player.grace += total_to_hp
	else:
		player.grace = maxi(player.grace, largest_hit)
	if player.grace > before:
		player.grace_turns_left = maxi(player.grace_window_turns, 1)
	return player.grace - before

# Combatant.buried follows the queued intent - under the sand exactly
# while a BURROW is what comes next.
static func _sync_buried(combatant: Combatant, data: EnemyData) -> void:
	var intent := current_intent(combatant, data)
	combatant.buried = intent != null and intent.type == EnemyIntent.IntentType.BURROW

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
