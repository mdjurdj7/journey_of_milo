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
	var result: Dictionary = {"attacked": false, "damage_to_hp": 0, "defended": false, "block_gained": 0, "grace_opened": 0, "interrupted": false, "buried": false, "surfaced": false, "countdown_damage": 0, "pain_turn": false, "pain_turn_triggered": false, "heal_allies": 0, "saved_heal": 0}

	Status.tick_all(combatant.statuses, func(amount: int) -> void:
		combatant.hp = max(combatant.hp - amount, 0)
	)
	# The tick just took a turn off every countdown (Sentence): one that
	# ran out goes off now, before this enemy acts - and if it kills, the
	# turn ends here. The HP it took is the controller's to report.
	result["countdown_damage"] = Status.resolve_countdowns(combatant)

	if combatant.hp <= 0 or data.intents.is_empty():
		return result

	# A drop below the pain line since the player's turn - that turn's own
	# drops are caught as they land (BattleController._report_damage()) -
	# or from the countdown just now: this turn's action is the one
	# cancelled.
	result["pain_turn_triggered"] = check_pain_turn(combatant, data)

	var intent := current_intent(combatant, data)
	var interjected: bool = combatant.interjected_intent != null
	if combatant.pain_turn_pending:
		# The pain turn: nothing resolves and nothing is queued in its
		# place - the loop moves on and the turn is counted, as if it had.
		combatant.pain_turn_pending = false
		result["pain_turn"] = true
	elif is_interrupted(combatant, intent):
		result["interrupted"] = true
	elif intent != null:
		match intent.type:
			EnemyIntent.IntentType.ATTACK:
				# One pass per hit (EnemyIntent.hits, 1 for every enemy so far):
				# modifiers are re-read each hit, so an Unflinching-shaped
				# status on the player - consumed by the first hit whether or
				# not damage reached HP, see status.gd's consume_triggered()
				# and StatusData.clears_on_trigger's own doc - only softens the
				# first, while one on this enemy that lasts the whole attack
				# (Braced, StatusData.consumed_by_own_attack) softens every
				# hit; block/absorb are worn down hit by hit.
				result["attacked"] = true
				var total_to_hp: int = 0
				# Tracked per hit as well as summed, because Grace's
				# LARGEST_HIT cap is about one hit, not the turn's total -
				# and DamagePipeline is the only thing that knows the split
				# between what block ate and what reached HP.
				var largest_hit: int = 0
				for hit in maxi(intent.hits, 1):
					var amount: int = hit_amount(combatant, data, intent, hit, player.statuses)
					Status.consume_triggered(player.statuses)
					# Critical is judged BEFORE the hit: Refuse the End saves a
					# player who was already there, not one this hit put there.
					var hp_before: int = player.hp
					var was_critical: bool = player.is_critical()
					var damage_result := DamagePipeline.resolve(amount, player)
					var to_hp: int = damage_result["damage_to_hp"]
					# Saved, what reached HP is what was actually lost - the
					# number the run's HP, the floating number and Grace all
					# take from here - and a save that left them higher than
					# before the hit (survive HP over what they had) lost
					# nothing and is a heal: "saved_heal", for the run's HP.
					if Status.refuse_lethal(player, was_critical):
						to_hp = maxi(hp_before - player.hp, 0)
						result["saved_heal"] += maxi(player.hp - hp_before, 0)
					total_to_hp += to_hp
					largest_hit = maxi(largest_hit, to_hp)
				# The attack has resolved, every hit of it: a status that
				# lasted only until then (Braced on this enemy) is spent -
				# even if the player's block ate all of it.
				Status.consume_after_attack(combatant.statuses)
				# ...and one on the player that lasted only until an attack
				# against them resolved (No Further's) goes, or spends a charge.
				Status.consume_after_attack_against(player.statuses)
				# Only now can the attack's HP loss grant anything (No
				# Further): after the attack, so it never softens itself.
				Status.resolve_critical_triggers(player)
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
			EnemyIntent.IntentType.HEAL_ALLY:
				# Its packmates are the controller's to heal - this side
				# knows only this enemy.
				result["heal_allies"] = intent.value

	# Counted whatever the turn did - an interrupted or cancelled one too -
	# so escalation keeps its own clock.
	combatant.turns_taken += 1
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
# gained for DEFEND, or the heal each packmate takes for HEAL_ALLY, as
# authored: BattleController caps it at what they're missing),
# "hit_amounts" (every hit's modified damage, in order - unequal when a
# once-per-Attack bonus lands on the first), "damage_to_hp" (total that would reach HP through
# block and absorb), "lethal" (it would take the player to 0 - replayed
# hit by hit on a local HP, so a lethal guard keeps it off: each hit it
# would save puts them at its survive HP, as many saves as it has
# charges - Status.refuse_lethal()). Empty when the enemy has no intent.
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
	# An escalating enemy says where it stands: the stage of the turn it is
	# about to take, 0-based, out of how many (the intent's pips).
	if not data.escalation_multipliers.is_empty():
		preview["escalation_stage"] = escalation_stage(combatant, data)
		preview["escalation_stages"] = data.escalation_multipliers.size()
	# The action a pain turn has cancelled: shown, but it won't resolve -
	# no number, never lethal.
	if combatant.pain_turn_pending:
		preview["pain_turn"] = true
		preview["per_hit"] = 0
		return preview
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
	var hp: int = player.hp
	var saves_used: int = 0
	var hits: int = maxi(intent.hits, 1)
	var hit_amounts: Array[int] = []
	for hit in hits:
		var amount: int = hit_amount(combatant, data, intent, hit, player_statuses)
		hit_amounts.append(amount)
		if hit == 0:
			preview["per_hit"] = amount
		Status.consume_triggered(player_statuses)
		var blocked: int = mini(block, amount)
		var after_block: int = amount - blocked
		var absorbed: int = mini(absorb, after_block)
		block -= blocked
		absorb -= absorbed
		total_to_hp += after_block - absorbed
		var was_critical: bool = player.is_critical_at(hp)
		hp -= after_block - absorbed
		if hp <= 0:
			var guard: Status = Status.lethal_guard(player_statuses, was_critical)
			if guard != null and saves_used < guard.charges:
				hp = guard.data.survive_hp(player.max_hp, player.critical_hp_fraction)
				saves_used += 1
	preview["hits"] = hits
	preview["hit_amounts"] = hit_amounts
	preview["damage_to_hp"] = total_to_hp
	preview["lethal"] = hp <= 0 and not bool(preview.get("interrupted", false))
	return preview

# The pain turn's trigger (EnemyData.pain_turn_hp_threshold): the first
# time this living enemy's HP is strictly below that fraction of its max,
# its next action is cancelled - once per fight. True only on the call
# that sets it, for the caller to announce.
static func check_pain_turn(combatant: Combatant, data: EnemyData) -> bool:
	if data == null or data.pain_turn_hp_threshold <= 0.0 or combatant.pain_turn_used or combatant.hp <= 0:
		return false
	if float(combatant.hp) >= float(combatant.max_hp) * data.pain_turn_hp_threshold:
		return false
	combatant.pain_turn_used = true
	combatant.pain_turn_pending = true
	return true

# The escalation stage of the turn this enemy is about to take (turns_
# taken + 1): (turn - 1) / escalation_stage_length, held at the last
# stage. 0 for an enemy that doesn't escalate.
static func escalation_stage(combatant: Combatant, data: EnemyData) -> int:
	if data == null or data.escalation_multipliers.is_empty():
		return 0
	var turn: int = combatant.turns_taken + 1
	return mini((turn - 1) / maxi(data.escalation_stage_length, 1), data.escalation_multipliers.size() - 1)

# What `intent` is worth on the turn this enemy is about to take: an
# ATTACK's value times its escalation stage's multiplier, rounded - before
# any status modifier. The one number take_turn() lands and preview_
# intent() shows. Anything else, and any enemy without escalation, is the
# value as authored.
static func intent_value(combatant: Combatant, data: EnemyData, intent: EnemyIntent) -> int:
	if intent.type != EnemyIntent.IntentType.ATTACK or data == null or data.escalation_multipliers.is_empty():
		return intent.value
	return roundi(float(intent.value) * data.escalation_multipliers[escalation_stage(combatant, data)])

# One hit of an ATTACK, before block: the intent's value (escalated),
# plus - on the first hit only - this enemy's once-per-Attack bonus
# (StatusData.attack_damage_bonus - Hungry), then its outgoing modifiers
# and the player's incoming ones. The one number take_turn() lands and
# preview_intent() shows, hit by hit; `player_statuses` is the player's
# list or the preview's copy of it.
static func hit_amount(combatant: Combatant, data: EnemyData, intent: EnemyIntent, hit: int, player_statuses: Array[Status]) -> int:
	var amount: int = intent_value(combatant, data, intent)
	if hit == 0:
		amount += Status.attack_bonus(combatant.statuses, combatant.is_critical())
	amount = Status.apply_modifiers(amount, combatant.statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
	return Status.apply_modifiers(amount, player_statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)

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

# The last of its pack (Combatant.pack_alone, from now on): a status
# waiting for that (Fed) gives way to its grant (Status.resolve_alone_
# triggers()), and a queued pack move (is_pack_move()) gives way to the
# next intent in the loop that isn't, as if it had been played. An
# interjection is left where it is. Returns whether the queued intent's
# number or the statuses changed, for the display to catch up.
static func leave_pack(combatant: Combatant, data: EnemyData) -> bool:
	combatant.pack_alone = true
	var changed: bool = Status.resolve_alone_triggers(combatant)
	var queued: EnemyIntent = current_intent(combatant, data)
	if combatant.interjected_intent != null or queued == null or not is_pack_move(queued):
		return changed
	_advance_intent(combatant, data)
	_sync_buried(combatant, data)
	return true

# A move only a pack makes - dropped from the loop once the enemy is the
# last of its pack: the dragonflies' simultaneous Swarm, and a heal for
# packmates (HEAL_ALLY - the Nipper's Forage).
static func is_pack_move(intent: EnemyIntent) -> bool:
	return intent != null and (intent.simultaneous or intent.type == EnemyIntent.IntentType.HEAL_ALLY)

static func _advance_intent(combatant: Combatant, data: EnemyData) -> void:
	if data.intents.is_empty():
		return
	if data.erratic_intent_selection:
		combatant.current_intent_index = _pick_erratic_intent_index(data, combatant.current_intent_index, combatant.pack_alone)
		return
	# Alone, the cycle steps over its pack moves - at most once round, so
	# a loop of nothing else still queues something.
	for _step in data.intents.size():
		combatant.current_intent_index = (combatant.current_intent_index + 1) % data.intents.size()
		if not combatant.pack_alone or not is_pack_move(data.intents[combatant.current_intent_index]):
			return

static func _pick_erratic_intent_index(data: EnemyData, previous_index: int, pack_alone: bool) -> int:
	var weights: Dictionary = {}
	for i in data.intents.size():
		var intent := data.intents[i]
		if i == previous_index and intent.no_immediate_repeat:
			continue
		if pack_alone and is_pack_move(intent):
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
