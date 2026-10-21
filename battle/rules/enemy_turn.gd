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
	# Dug in from the start (EnemyData.opens_dug_in): the loop's first DIG
	# already done, the loop waiting on the move after it.
	if data.opens_dug_in and not data.erratic_intent_selection:
		for index in data.intents.size():
			var intent: EnemyIntent = data.intents[index]
			if intent != null and intent.type == EnemyIntent.IntentType.DIG:
				start_dig(combatant, intent)
				if combatant.dug_in:
					combatant.current_intent_index = (index + 1) % data.intents.size()
				break
	_sync_queued(combatant, data)

# The queued intent: under the sand after a DIG, its next move there
# (EnemyIntent.under_moves); else an interjection (an interrupted
# intent's on_interrupt) when one is waiting; else the loop's own.
static func current_intent(combatant: Combatant, data: EnemyData) -> EnemyIntent:
	if combatant.dug_in and combatant.dig_intent != null and combatant.dug_step < combatant.dig_intent.under_moves.size():
		return combatant.dig_intent.under_moves[combatant.dug_step]
	if combatant.interjected_intent != null:
		return combatant.interjected_intent
	if data.intents.is_empty() or combatant.current_intent_index < 0:
		return null
	return data.intents[combatant.current_intent_index]

# What breaks `intent` now: its interrupt_threshold with what this
# enemy's statuses add to it (StatusData.interrupt_threshold_change - Off
# the rock), at least 1; 0 for an intent that can't be broken. The one
# number the break, the ring and the run log read.
static func interrupt_threshold(combatant: Combatant, intent: EnemyIntent) -> int:
	if intent == null or intent.type != EnemyIntent.IntentType.ATTACK or intent.interrupt_threshold <= 0:
		return 0
	return maxi(intent.interrupt_threshold + Status.interrupt_threshold_change(combatant.statuses), 1)

# Whether the queued intent's interrupt threshold has been met by what
# the player has dealt this turn - the attack won't land.
static func is_interrupted(combatant: Combatant, intent: EnemyIntent) -> bool:
	var threshold: int = interrupt_threshold(combatant, intent)
	if threshold <= 0:
		return false
	return combatant.damage_taken_this_turn >= threshold

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
	var result: Dictionary = {"intent": "", "hits": [], "attacked": false, "damage_to_hp": 0, "defended": false, "block_gained": 0, "block_cleared": 0, "grace_opened": 0, "interrupted": false, "buried": false, "surfaced": false, "countdown_damage": 0, "pain_turn": false, "pain_turn_triggered": false, "phase_triggered": false, "heal_allies": 0, "saved_heal": 0, "denied": false, "delayed": false, "blocked": 0, "absorbed": 0, "tolled": 0, "applied_to_player": 0}

	# Its Block is gone as its own turn starts, as the player's is at
	# theirs (BattleController._start_player_turn()): what a Defend gained
	# guards it through the player's next turn and no longer. Every turn
	# clears it - a pain turn, a Denied one, one under the sand. Absorb is
	# untouched. "block_cleared" is what went, for the readout.
	result["block_cleared"] = combatant.block
	combatant.block = 0

	Status.tick_all(combatant.statuses, func(amount: int, _ticking: Status) -> void:
		combatant.hp = max(combatant.hp - amount, 0)
	)
	# The tick just took a turn off every countdown (Sentence): one that
	# ran out goes off now, before this enemy acts - and if it kills, the
	# turn ends here. The HP it took is the controller's to report.
	result["countdown_damage"] = Status.resolve_countdowns(combatant)

	if combatant.hp <= 0 or data.intents.is_empty():
		return result

	# Dormant: its statuses have ticked and a countdown has gone off, and
	# that is all - no action, nothing spent, the loop and the turn count
	# waiting until it wakes.
	if combatant.dormant:
		result["dormant"] = true
		Status.remove_expired(combatant.statuses)
		return result

	# A drop below the pain line since the player's turn - that turn's own
	# drops are caught as they land (BattleController._report_damage()) -
	# or from the countdown just now: this turn's action is the one
	# cancelled.
	result["pain_turn_triggered"] = check_pain_turn(combatant, data)
	# ...and a drop below the phase line, the same way: its status is up
	# before this turn's move reads it.
	result["phase_triggered"] = check_phase(combatant, data)

	result["dug"] = false
	result["erupted"] = false
	var intent := current_intent(combatant, data)
	# Under the sand (a DIG's): this turn is one of its moves there, the
	# loop held where the Dig left it.
	var under: bool = combatant.dug_in
	var interjected: bool = not under and combatant.interjected_intent != null
	# For the run log: which move this was, and each hit of it.
	result["intent"] = intent.intent_name if intent != null else ""
	# Stunned (StatusData.skips_next_turn): spent by this turn whatever
	# happens, so it never carries over - a pain turn landing on the same
	# turn takes it too.
	var denied: Status = Status.skip_turn_status(combatant.statuses)
	if denied != null:
		combatant.statuses.erase(denied)
		result["denied"] = true
	# What its last move brought (EnemyIntent.status_on_resolve - Coiled)
	# lasts until this one, however this one goes.
	for brought: StatusData in _resolved_statuses(data):
		var held: Status = Status.find_in(combatant.statuses, brought)
		if held != null:
			Status.remove_from(combatant.statuses, held)
	# Delayed (Deny - StatusData.delays_next_action): this turn does
	# nothing and its move waits for the next - held where it is (the loop,
	# an interjection, a dig's step), its marks still bound to it, the turn
	# count not moving (an escalation paused). A pain turn due now is spent
	# on it. Delayed goes with this turn.
	var delayed: Status = Status.delay_status(combatant.statuses)
	if delayed != null:
		combatant.statuses.erase(delayed)
		result["delayed"] = true
		if combatant.pain_turn_pending:
			combatant.pain_turn_pending = false
			result["pain_turn"] = true
		Status.remove_expired(combatant.statuses)
		_sync_queued(combatant, data)
		result["buried"] = combatant.buried
		return result
	if combatant.pain_turn_pending:
		# The pain turn: nothing resolves and nothing is queued in its
		# place - the loop moves on and the turn is counted, as if it had.
		combatant.pain_turn_pending = false
		result["pain_turn"] = true
	elif denied != null:
		# Stunned: the same as a pain turn - the move is lost, not delayed;
		# an interruptible one isn't "interrupted", so nothing is queued.
		pass
	elif is_interrupted(combatant, intent):
		result["interrupted"] = true
		# Broken, what the Attack cards fed it (Goaded) goes with it - the
		# next one starts from its own number.
		if intent.counts_attack_cards and data.attack_card_status != null:
			var fed: Status = Status.find_in(combatant.statuses, data.attack_card_status)
			if fed != null:
				Status.remove_from(combatant.statuses, fed)
	elif intent != null:
		match intent.type:
			EnemyIntent.IntentType.ATTACK:
				# Each attack of the turn (repeats() - Bereft's two) in
				# "actions", one after another, and summed into the turn's
				# own keys; a turn's one attack is the same, once.
				var actions: Array[Dictionary] = []
				# What the marks on it changed, summed over every action
				# (land_attack()'s "mark_numbers").
				var mark_numbers: Dictionary = {}
				result["mark_numbers"] = mark_numbers
				for action in repeats(combatant, intent):
					# Either side down ends it - the enemy too, killed by
					# what came back off its last attack (hit_back_damage).
					if player.hp <= 0 or combatant.hp <= 0:
						break
					var attack: Dictionary = {"intent": result["intent"], "hits": [], "attacked": false, "damage_to_hp": 0, "grace_opened": 0, "saved_heal": 0, "blocked": 0, "absorbed": 0, "tolled": 0, "applied_to_player": 0, "mark_numbers": mark_numbers}
					land_attack(combatant, data, intent, player, attack, intent.lands_as_strike_back, action > 0)
					# What the attack leaves on the player (the Adder's Venom)
					# lands whatever its hits did - Block taking all of them too.
					if intent.applies_to_player != null and intent.applied_amount > 0:
						Status.apply_amount(player.statuses, intent.applies_to_player, intent.applied_amount)
						attack["applied_to_player"] = intent.applied_amount
					actions.append(attack)
					result["attacked"] = true
					(result["hits"] as Array).append_array(attack["hits"])
					for key: String in ["damage_to_hp", "grace_opened", "saved_heal", "blocked", "absorbed", "tolled", "applied_to_player"]:
						result[key] += attack[key]
				result["actions"] = actions
			EnemyIntent.IntentType.DEFEND:
				var gained: int = intent.value * repeats(combatant, intent)
				combatant.block += gained
				result["defended"] = true
				result["block_gained"] = gained
			EnemyIntent.IntentType.BURROW:
				result["surfaced"] = true
			EnemyIntent.IntentType.HEAL_ALLY:
				# Its packmates are the controller's to heal - this side
				# knows only this enemy.
				result["heal_allies"] = intent.value
			EnemyIntent.IntentType.WATCH:
				# Nothing happens: the turn is watched through.
				pass
			EnemyIntent.IntentType.SETTLE:
				# Nothing happens here: it settles, and what it holds next
				# changes with the queued intent (_sync_queued(), below).
				pass
			EnemyIntent.IntentType.COIL:
				# Nothing happens here either: it coils, and what that brings
				# is its status_on_resolve (Coiled), just below.
				pass
			EnemyIntent.IntentType.TAUNT:
				# As the Coil: it puffs up, and what that brings is its
				# status_on_resolve (Inflated), just below.
				pass
			EnemyIntent.IntentType.SIGNAL:
				# Its pack is the controller's to call - this side knows
				# only this enemy (BattleController._answer_signal()).
				result["signal"] = true
			EnemyIntent.IntentType.DIG:
				# Under the sand, its mounds up (start_dig()); the loop moves
				# on past the Dig below, for when it comes back up.
				start_dig(combatant, intent)
				result["dug"] = combatant.dug_in
		# The move resolved: what it brings, until the next (the Coil's
		# Coiled). A move lost or broken, above, brings nothing.
		if intent.status_on_resolve != null:
			Status.apply_to(combatant.statuses, intent.status_on_resolve)
	# What lived on its intent (StatusData.intent_mark - Braced, Garnished,
	# Wrested): it cut the first action, and is spent once that intent has
	# landed; lost, with
	# why, if this turn's move was another or didn't land. "marks": one
	# entry each (_settle_marks()).
	result["marks"] = _settle_marks(combatant, intent, result)

	# Counted whatever the turn did - an interrupted or cancelled one too -
	# so escalation keeps its own clock.
	combatant.turns_taken += 1
	Status.remove_expired(combatant.statuses)
	if combatant.hp > 0:
		# A turn under the sand steps through its moves there - lost to a
		# pain turn or Stunned, the count goes on - and the last surfaces it
		# on its own: "erupted", at true_mound. The loop is where the Dig
		# left it.
		if under:
			combatant.dug_step += 1
			if combatant.dig_intent == null or combatant.dug_step >= combatant.dig_intent.under_moves.size():
				_end_dig(combatant)
				result["erupted"] = true
		# An interjection resolved leaves the loop where it was - the loop
		# already moved past the intent it replaced.
		elif interjected:
			combatant.interjected_intent = null
		else:
			_advance_intent(combatant, data)
		if result["interrupted"]:
			combatant.interjected_intent = intent.on_interrupt
		_sync_queued(combatant, data)
		result["buried"] = combatant.buried
	return result

# One ATTACK landing on the player, every hit of it, into `result` (take_
# turn()'s keys: "attacked", "hits", "blocked", "absorbed", "saved_heal",
# "damage_to_hp", "grace_opened") - an intent's on the enemy's turn, or a
# strike back's in the player's (counter_strike()), the same way.
#
# One pass per hit (hit_count() - EnemyIntent.hits, and more off the
# rock): modifiers are re-read each hit, so an Unflinching-shaped status
# on the player - consumed by the first hit whether or not damage reached
# HP, see status.gd's consume_triggered() and StatusData.clears_on_
# trigger's own doc - only softens the first, while one on this enemy that
# lasts the whole attack (Braced, StatusData.consumed_by_own_attack)
# softens every hit; block/absorb are worn down hit by hit.
#
# `strike_back`: the hit answers a card in the player's turn (counter_
# strike()), or lands as one does (EnemyIntent.lands_as_strike_back - the
# Siltjaw's Erupt) - the statuses that wait for the enemy's own turn
# (StatusData.ignores_strike_backs: Braced, Garnished, No Further's armed,
# Unbroken's) neither soften it nor are spent by it.
#
# `repeat_action`: a second action of an intent carried out twice (Bereft)
# - every mark on the intent (Status.marks() - Braced, Garnished, Wrested)
# cuts the action it was put on, the first, so this one reads its statuses
# without them and lands in full.
static func land_attack(combatant: Combatant, data: EnemyData, intent: EnemyIntent, player: Combatant, result: Dictionary, strike_back: bool = false, repeat_action: bool = false) -> void:
	result["attacked"] = true
	var total_to_hp: int = 0
	# Tracked per hit as well as summed, because Grace's LARGEST_HIT cap is
	# about one hit, not the turn's total - and DamagePipeline is the only
	# thing that knows the split between what block ate and what reached HP.
	var largest_hit: int = 0
	# What the attack loses in all (Garnished on this enemy, Unbroken on the
	# player), soaked hit by hit.
	# A strike back reads neither (Status.strike_back_view()).
	var own_statuses: Array[Status] = Status.strike_back_view(combatant.statuses) if strike_back else combatant.statuses
	if repeat_action:
		own_statuses = Status.without(own_statuses, Status.marks(own_statuses))
	var player_statuses: Array[Status] = Status.strike_back_view(player.statuses) if strike_back else player.statuses
	var reduction_left: int = Status.attack_total_reduction(own_statuses) + Status.attack_total_reduction(player_statuses)
	# What lives on the intent (StatusData.intent_mark - Braced, Garnished;
	# never on a strike back), and what each takes off this attack, for
	# "mark_numbers": a modifier (Braced) its hits before and after it, a
	# total reduction (Garnished) its hits before and after its share of
	# the cut - its share soaked first.
	var marked: Array[Status] = Status.marks(own_statuses)
	var numbers: Dictionary = result.get("mark_numbers", {})
	var mark_left: Dictionary = {}
	for active in marked:
		if active.data.reduces_attack_total:
			mark_left[active] = maxi(active.magnitude, 0)
	for hit in hit_count(combatant, intent):
		var amount: int = hit_amount(combatant, data, intent, hit, player.statuses, strike_back)
		if not marked.is_empty():
			var plain: int = _hit_amount_seen(combatant, data, intent, Status.without(own_statuses, marked), player.statuses)
			for active in marked:
				if active.data.category == StatusData.Category.MODIFIER:
					_tally_mark(numbers, active.data.intent_mark, plain, amount)
		var cut: int = reduce_hit(amount, reduction_left)
		var share_left: int = cut
		for active: Status in mark_left:
			var share: int = mini(share_left, int(mark_left[active]))
			mark_left[active] = int(mark_left[active]) - share
			share_left -= share
			_tally_mark(numbers, active.data.intent_mark, amount, amount - share)
		amount -= cut
		reduction_left -= cut
		# The worn piece's first hit (first_hit_scale): this one, if it is
		# the first to get past Block and absorb - scaled before them.
		if takes_first_hit(player.first_hit_scale, player.first_hit_spent, amount, player.block, player.absorb):
			amount = scaled_first_hit(amount, player.first_hit_scale)
			player.first_hit_spent = true
			result["first_hit_scaled"] = true
		Status.consume_triggered(player.statuses)
		# Critical is judged BEFORE the hit: Refuse the End saves a player
		# who was already there, not one this hit put there.
		var hp_before: int = player.hp
		var was_critical: bool = player.is_critical()
		var damage_result := DamagePipeline.resolve(amount, player)
		var to_hp: int = damage_result["damage_to_hp"]
		# What the player's block and absorb took, for the run log.
		result["blocked"] += damage_result["blocked"]
		result["absorbed"] += damage_result["absorbed"]
		# What Toll paid of it (Thick Skin - DamagePipeline.resolve()).
		result["tolled"] = int(result.get("tolled", 0)) + int(damage_result["tolled"])
		# Saved, what reached HP is what was actually lost - the number the
		# run's HP, the floating number and Grace all take from here - and a
		# save that left them higher than before the hit (survive HP over
		# what they had) lost nothing and is a heal: "saved_heal", for the
		# run's HP.
		# The heal is kept on its hit too, so the run's HP can take the
		# attack in the order the fight did (BattleController._report_
		# enemy_attack()).
		var saved: int = 0
		if Status.refuse_lethal(player, was_critical):
			to_hp = maxi(hp_before - player.hp, 0)
			saved = maxi(player.hp - hp_before, 0)
			result["saved_heal"] += saved
		total_to_hp += to_hp
		largest_hit = maxi(largest_hit, to_hp)
		(result["hits"] as Array).append({"damage": amount, "blocked": damage_result["blocked"], "absorbed": damage_result["absorbed"], "tolled": damage_result["tolled"], "to_hp": to_hp, "saved_heal": saved})
	# The attack has resolved, every hit of it: a status that lasted only
	# until then (Braced on this enemy) is spent - even if the player's
	# block ate all of it.
	Status.consume_after_attack(combatant.statuses, held_back(data, intent), strike_back)
	# ...and one on the player that lasted only until an attack against
	# them resolved (No Further's) goes, or spends a charge - a strike back
	# passing both by.
	Status.consume_after_attack_against(player.statuses, strike_back)
	# Only now can the attack's HP loss grant anything (No Further): after
	# the attack, so it never softens itself.
	Status.resolve_critical_triggers(player)
	result["damage_to_hp"] = total_to_hp
	if total_to_hp > 0:
		player.took_damage_this_turn = true
		result["grace_opened"] = open_grace(player, largest_hit, total_to_hp)
		# On the record for Not So: the whole attack, every hit of it.
		player.record_hit_taken(combatant, intent.intent_name if intent != null else "", total_to_hp, grace_share(player, largest_hit, total_to_hp))
	# The worn piece's damage back (hit_back_damage): once for the attack,
	# however many hits and whatever Block took, through the enemy's own
	# Block - ordinary damage, not an Attack card, so nothing strikes back
	# at it. "hit_back" is what reached HP, the controller's to report.
	if player.hit_back_damage > 0 and player.hp > 0 and combatant.hp > 0:
		var back: Dictionary = DamagePipeline.resolve(player.hit_back_damage, combatant)
		result["hit_back"] = back["damage_to_hp"]

# Whether a hit of `amount`, against `block` and `absorb`, is the one the
# worn piece's first hit takes (Combatant.first_hit_scale): one is armed
# (scale under 1, not yet spent) and this hit would get past both. A
# fully blocked hit leaves it armed. The one rule land_attack() spends
# and preview_intent() replays.
static func takes_first_hit(scale: float, spent: bool, amount: int, block: int, absorb: int) -> bool:
	return scale < 1.0 and not spent and amount > block + absorb

# That hit, scaled: rounded down, never below 0.
static func scaled_first_hit(amount: int, scale: float) -> int:
	return floori(float(amount) * clampf(scale, 0.0, 1.0))

# The strike back (StatusData.strikes_back_on_attack_card - the Adder's
# Coiled): an Attack card has just been played against this living enemy,
# and it answers with one hit of the status's magnitude - an ATTACK in
# every way, through land_attack() as a strike back - its attack bonuses
# and modifiers, Block, Refuse the End, Grace - except that Braced,
# Garnished, No Further's armed and Unbroken's wait for its own turn,
# neither softening it nor spent by it. "intent" is the status's name, for the run log ("adder:Coiled").
# Empty when it holds nothing that strikes back, or either side is down.
static func counter_strike(combatant: Combatant, data: EnemyData, player: Combatant) -> Dictionary:
	if combatant == null or player == null or combatant.hp <= 0 or player.hp <= 0:
		return {}
	var coiled: Status = null
	for active in combatant.statuses:
		if active.data != null and active.data.strikes_back_on_attack_card and active.magnitude > 0:
			coiled = active
			break
	if coiled == null:
		return {}
	var strike := EnemyIntent.new()
	strike.intent_name = coiled.data.display_name
	strike.value = coiled.magnitude
	var result: Dictionary = {"intent": strike.intent_name, "hits": [], "attacked": false, "damage_to_hp": 0, "grace_opened": 0, "saved_heal": 0, "blocked": 0, "absorbed": 0, "tolled": 0}
	land_attack(combatant, data, strike, player, result, true)
	return result

# What the queued intent WILL do if it resolves now, for the intent
# display - the exact arithmetic take_turn() runs, on copies, mutating
# nothing real (replay_attack(), on `state`). Keys: "type"
# (EnemyIntent.IntentType), "hits", "per_hit"
# (the first hit's modified damage - the M of what "M×N" shows - or the block
# gained for DEFEND, or the heal each packmate takes for HEAL_ALLY, as
# authored: BattleController caps it at what they're missing),
# "hit_amounts" (every hit's modified damage, in order - unequal when a
# status on the player is consumed by the first hit, as No Further's 0
# is), "damage_to_hp" (total that would reach HP through
# block and absorb), "lethal" (it would take the player to 0 - these hits
# alone from where he stands, simulate_hits(), so a lethal guard keeps it
# off: each hit it would save puts them at its survive HP, as many saves
# as it has charges - Status.refuse_lethal()). Empty when the enemy has
# no intent.
#
# An ATTACK with an interrupt_threshold also carries "threshold" (what
# breaks it now - interrupt_threshold()), "threshold_left" (what the
# player still has to deal this turn, down to 0) and "interrupted" (it's
# been met - the attack won't land, so never lethal).
#
# `state` (turn_state()) is the player as the enemies before this one in
# the coming turn leave him - what their hits spend (the worn piece's
# first hit, No Further's armed, Block) gone, Unbroken's still up for
# each - and this
# one's hits are read from it and spend from it in turn, so each enemy's
# numbers are the ones that will land (BattleController's previews pass
# one along in turn order). Empty = the player as he stands, alone.
static func preview_intent(combatant: Combatant, data: EnemyData, player: Combatant, state: Dictionary = {}) -> Dictionary:
	var intent := current_intent(combatant, data)
	# Dormant: nothing shown until it wakes.
	if intent == null or combatant.dormant:
		return {}
	var preview: Dictionary = {"type": intent.type, "hits": 1, "per_hit": intent.value, "damage_to_hp": 0, "lethal": false}
	# An escalating enemy says where it stands: the stage of the turn it is
	# about to take, 0-based, out of how many (the intent's pips).
	if not data.escalation_multipliers.is_empty():
		preview["escalation_stage"] = escalation_stage(combatant, data)
		preview["escalation_stages"] = data.escalation_multipliers.size()
	# Under the sand: which of its turns there this is, of how many before
	# it erupts (the intent's pips) - never which mound.
	if combatant.dug_in and combatant.dig_intent != null:
		preview["dig_stage"] = combatant.dug_step
		preview["dig_stages"] = combatant.dig_intent.under_moves.size()
	# The action a pain turn has cancelled: shown, but it won't resolve -
	# no number, never lethal.
	if combatant.pain_turn_pending:
		preview["pain_turn"] = true
		preview["per_hit"] = 0
		return preview
	# Stunned: the move keeps its number - the display shows what was
	# denied, struck through - but it won't resolve, so it reaches nothing
	# and is never lethal. Delayed (Deny) the same this turn, dimmed rather
	# than struck: it lands on the turn after.
	var denied: bool = is_denied(combatant)
	if denied:
		preview["denied"] = true
	var delayed: bool = is_delayed(combatant)
	if delayed:
		preview["delayed"] = true
	# Carried out more than once (repeats() - Bereft): "repeats" says how
	# often; a DEFEND's number is all the Block it gains, an ATTACK's hits
	# are every hit of every attack, in order.
	var times: int = repeats(combatant, intent)
	if times > 1:
		preview["repeats"] = times
	if intent.type == EnemyIntent.IntentType.DEFEND:
		preview["per_hit"] = intent.value * times
	if intent.type != EnemyIntent.IntentType.ATTACK:
		return preview
	var threshold: int = interrupt_threshold(combatant, intent)
	if threshold > 0:
		preview["threshold"] = threshold
		preview["threshold_left"] = maxi(threshold - combatant.damage_taken_this_turn, 0)
		preview["interrupted"] = is_interrupted(combatant, intent)
	if state.is_empty():
		state.merge(turn_state(player))
	# What it would land, from where the enemies before it leave him; a
	# move that won't land this turn (Stunned, Delayed, broken) shows its
	# hits but spends nothing of `state` - those after it read him as it
	# found him.
	var lands: bool = not denied and not delayed and not bool(preview.get("interrupted", false))
	var replay: Dictionary = state if lands else copy_state(state)
	var hits: int = hit_count(combatant, intent)
	var hit_amounts: Array[int] = []
	# Every attack of the turn, replayed in turn on the same state; a later
	# one reads the enemy as the one before left it - what an attack spends
	# on either side gone.
	var attacker: Combatant = combatant
	# One that lands as a strike back (EnemyIntent.lands_as_strike_back -
	# the Erupt) reads neither side's statuses that wait for the enemy's
	# own turn, as land_attack() does.
	var strike_back: bool = intent.lands_as_strike_back
	for action in times:
		if action > 0:
			attacker = _after_own_attack(combatant, data, intent)
		hit_amounts.append_array(replay_attack(attacker, data, intent, player, replay, strike_back))
	if not hit_amounts.is_empty():
		preview["per_hit"] = hit_amounts[0]
	preview["hits"] = hits * times
	preview["hit_amounts"] = hit_amounts
	# Alone: these hits from where he stands now - the warning across
	# enemies (BattleController._lethal_together()) reads the turn as a
	# whole.
	var alone: Dictionary = simulate_hits(player, hit_amounts)
	preview["damage_to_hp"] = 0 if not lands and not bool(preview.get("interrupted", false)) else int(alone["to_hp"])
	preview["lethal"] = bool(alone["lethal"]) and lands
	# What lives on this intent (StatusData.intent_mark - Braced,
	# Garnished): "marks", their names in order ("brace" before
	# "garnish") - the readout's hairline under its numeral.
	var marked: Array[Status] = Status.marks(combatant.statuses)
	if not marked.is_empty() and not strike_back:
		var names: Array[StringName] = []
		for active in marked:
			names.append(active.data.intent_mark)
		names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		preview["marks"] = names
	return preview

# Hits landing on `player` in order, from where they stand now: each
# through Block, then absorb, then HP, a lethal guard saving them as it
# would (preview_intent()'s own replay). "to_hp": what reaches HP in all;
# "lethal": whether the last of them leaves them at 0. Nothing is changed.
static func simulate_hits(player: Combatant, amounts: Array[int]) -> Dictionary:
	var block: int = player.block
	var absorb: int = player.absorb
	# Toll pays what's past them while Thick Skin is up (DamagePipeline).
	var toll: int = maxi(player.toll, 0) if Status.toll_payer(player.statuses) != null else 0
	var hp: int = player.hp
	var saves_used: int = 0
	var total_to_hp: int = 0
	for amount in amounts:
		var blocked: int = mini(block, amount)
		var after_block: int = amount - blocked
		var absorbed: int = mini(absorb, after_block)
		var tolled: int = mini(toll, after_block - absorbed)
		block -= blocked
		absorb -= absorbed
		toll -= tolled
		total_to_hp += after_block - absorbed - tolled
		var was_critical: bool = player.is_critical_at(hp)
		hp -= after_block - absorbed - tolled
		if hp <= 0:
			var guard: Status = Status.lethal_guard(player.statuses, was_critical)
			if guard != null and saves_used < guard.charges:
				hp = guard.data.survive_hp(player.max_hp, player.critical_fraction())
				saves_used += 1
	return {"to_hp": total_to_hp, "lethal": hp <= 0}

# The player as the coming enemy turn finds him, for the previews to
# spend from in turn (preview_intent()'s `state`): his statuses as
# copies (Status.clones() - spending one here touches nothing real),
# whether the worn piece's first hit is spent, Block, absorb, HP and the
# lethal guard's saves used so far.
static func turn_state(player: Combatant) -> Dictionary:
	return {"statuses": Status.clones(player.statuses), "first_hit_spent": player.first_hit_spent, "block": player.block, "absorb": player.absorb, "toll": player.toll, "hp": player.hp, "saves_used": 0}

static func copy_state(state: Dictionary) -> Dictionary:
	var copy: Dictionary = state.duplicate()
	copy["statuses"] = Status.clones(state["statuses"])
	return copy

# One attack of `attacker`'s landing on `state` - land_attack()'s
# arithmetic, replayed: each hit's damage (its modifiers, then the total
# reductions soaked hit by hit - Garnished on it, Unbroken on him - then
# the worn piece's first hit, if this is the first to get past Block and
# absorb), worn through Block, absorb and HP, the lethal guard saving as
# it would; then what lasted until an attack against him resolved (No
# Further's) goes - Unbroken's stays, for the next attack too. `state` is
# changed; nothing real is. The hits' damage, in order.
static func replay_attack(attacker: Combatant, data: EnemyData, intent: EnemyIntent, player: Combatant, state: Dictionary, strike_back: bool = false) -> Array[int]:
	var theirs: Array[Status] = state["statuses"]
	var own_seen: Array[Status] = Status.strike_back_view(attacker.statuses) if strike_back else attacker.statuses
	var theirs_seen: Array[Status] = Status.strike_back_view(theirs) if strike_back else theirs
	var reduction_left: int = Status.attack_total_reduction(own_seen) + Status.attack_total_reduction(theirs_seen)
	var amounts: Array[int] = []
	for hit in hit_count(attacker, intent):
		var amount: int = hit_amount(attacker, data, intent, hit, theirs, strike_back)
		var cut: int = reduce_hit(amount, reduction_left)
		amount -= cut
		reduction_left -= cut
		if takes_first_hit(player.first_hit_scale, bool(state["first_hit_spent"]), amount, int(state["block"]), int(state["absorb"])):
			amount = scaled_first_hit(amount, player.first_hit_scale)
			state["first_hit_spent"] = true
		amounts.append(amount)
		Status.consume_triggered(theirs)
		var blocked: int = mini(int(state["block"]), amount)
		var after_block: int = amount - blocked
		var absorbed: int = mini(int(state["absorb"]), after_block)
		state["block"] = int(state["block"]) - blocked
		state["absorb"] = int(state["absorb"]) - absorbed
		# Toll pays what's past them (Thick Skin), as DamagePipeline does.
		var tolled: int = 0
		if Status.toll_payer(theirs) != null:
			tolled = mini(maxi(int(state.get("toll", 0)), 0), after_block - absorbed)
			state["toll"] = int(state.get("toll", 0)) - tolled
		var hp: int = int(state["hp"])
		var was_critical: bool = player.is_critical_at(hp)
		hp -= after_block - absorbed - tolled
		if hp <= 0:
			var guard: Status = Status.lethal_guard(theirs, was_critical)
			if guard != null and int(state["saves_used"]) < guard.charges:
				hp = guard.data.survive_hp(player.max_hp, player.critical_fraction())
				state["saves_used"] = int(state["saves_used"]) + 1
		state["hp"] = hp
	Status.consume_after_attack_against(theirs, strike_back)
	return amounts

# One Attack card has been played against this living enemy: while its
# queued intent counts them (EnemyIntent.counts_attack_cards - the
# Dunecur's Rush), a stack of its attack_card_status (Roused), up to that
# status's max_stacks. A Denied Rush still has it queued, and what it
# gained stays until a Rush lands (StatusData.consumed_by_own_attack).
# True when it gained a stack, for the display to catch up.
static func take_attack_card(combatant: Combatant, data: EnemyData) -> bool:
	if combatant == null or data == null or data.attack_card_status == null or combatant.hp <= 0:
		return false
	var intent: EnemyIntent = current_intent(combatant, data)
	if intent == null or not intent.counts_attack_cards:
		return false
	Status.apply_to(combatant.statuses, data.attack_card_status)
	return true

# The enemy's attack-card status (Roused) belongs to the intents that
# count Attack cards (the Rush): only they add its bonus and spend it. On
# any other intent (the Snarl) it is held back - neither paid nor spent -
# and waits for the next that counts, so a Denied Rush's stacks go into
# the next Rush. Null when nothing is held back.
static func held_back(data: EnemyData, intent: EnemyIntent) -> StatusData:
	if data == null or intent == null or intent.counts_attack_cards:
		return null
	return data.attack_card_status

# How many times this enemy carries out `intent` this turn: what its
# statuses ask (StatusData.repeats_intent - Bereft) for an ATTACK or a
# DEFEND, once for anything else. The one count take_turn() resolves and
# preview_intent() shows.
static func repeats(combatant: Combatant, intent: EnemyIntent) -> int:
	if intent == null or (intent.type != EnemyIntent.IntentType.ATTACK and intent.type != EnemyIntent.IntentType.DEFEND):
		return 1
	return Status.intent_repeats(combatant.statuses)

# The enemy as a repeated attack after its first finds it: its own
# statuses spent by an attack (StatusData.consumed_by_own_attack) gone,
# and every mark on the intent (Status.marks() - Braced, Garnished,
# Wrested), which cut the first action only; the rest as they are - a
# copy, for the preview to read the next attack's hits off without
# touching the real one.
static func _after_own_attack(combatant: Combatant, data: EnemyData, intent: EnemyIntent) -> Combatant:
	var shadow := Combatant.new(combatant.max_hp)
	shadow.hp = combatant.hp
	shadow.critical_hp_fraction = combatant.critical_hp_fraction
	shadow.turns_taken = combatant.turns_taken
	shadow.statuses = Status.without(combatant.statuses, Status.marks(combatant.statuses))
	Status.consume_after_attack(shadow.statuses, held_back(data, intent))
	return shadow

# How many hits an ATTACK lands: EnemyIntent.hits (at least 1), and a
# multi-hit one gains what its statuses add (StatusData.bonus_hits - Off
# the rock's Tail Lash) - a single blow stays single. The one count take_
# turn() lands and preview_intent() shows.
static func hit_count(combatant: Combatant, intent: EnemyIntent) -> int:
	var hits: int = maxi(intent.hits, 1)
	if hits > 1:
		hits += maxi(Status.bonus_hits(combatant.statuses), 0)
	return hits

# Whether this enemy's next turn is skipped (Denied).
# Why a card marking an intent (StatusData.intent_mark - Brace, Garnish)
# may not target this enemy's queued intent: NONE when it may - an attack
# that will land when it resolves, not one that lands as a strike back
# (the Erupt), carrying no `status_data` mark yet. NO_INTENT: nothing
# shown (dormant, dead); NOT_ATTACK; ONLY_BLOCK (lands as a strike back);
# WONT_LAND (Stunned, a pain turn's, an interrupted one); ALREADY. A
# Delayed move (Deny) takes one: it lands, a turn later.
enum MarkRefusal { NONE, NO_INTENT, NOT_ATTACK, ONLY_BLOCK, WONT_LAND, ALREADY }

static func mark_refusal(combatant: Combatant, data: EnemyData, status_data: StatusData) -> MarkRefusal:
	if combatant == null or data == null or combatant.hp <= 0 or combatant.dormant:
		return MarkRefusal.NO_INTENT
	var intent: EnemyIntent = current_intent(combatant, data)
	if intent == null:
		return MarkRefusal.NO_INTENT
	if intent.type != EnemyIntent.IntentType.ATTACK:
		return MarkRefusal.NOT_ATTACK
	if intent.lands_as_strike_back:
		return MarkRefusal.ONLY_BLOCK
	if combatant.pain_turn_pending or is_denied(combatant) or is_interrupted(combatant, intent):
		return MarkRefusal.WONT_LAND
	var held: Status = Status.find_mark(combatant.statuses, status_data.intent_mark) if status_data != null else null
	if held != null and held.bound_intent == intent:
		return MarkRefusal.ALREADY
	return MarkRefusal.NONE

# Whether a status living on an intent (StatusData.intent_mark) still
# holds in the player's turn: "" while its intent is queued and will
# land; "replaced" once another is queued (a pack move dropped, the
# Siltjaw up through its mound); "cancelled" once it won't land (Stunned,
# a pain turn, an interrupt met). A Delayed move keeps its marks.
static func mark_loss(active: Status, combatant: Combatant, data: EnemyData) -> String:
	var intent: EnemyIntent = current_intent(combatant, data) if data != null else null
	if intent == null or intent != active.bound_intent or combatant.dormant:
		return "replaced"
	if combatant.pain_turn_pending or is_denied(combatant) or is_interrupted(combatant, intent):
		return "cancelled"
	return ""

# The enemy's turn is done: each status living on an intent (Status.
# marks()) leaves it - "spent" when its intent was the move that landed
# (with "before" and "after": the hits' total either side of it, from
# land_attack()'s "mark_numbers"), "lost" otherwise, with "reason":
# "replaced" (another move came) or "cancelled" (it didn't land). Each
# entry names its "mark", "status", "intent" and the card that put it on
# ("granted_by").
static func _settle_marks(combatant: Combatant, intent: EnemyIntent, result: Dictionary) -> Array[Dictionary]:
	var settled: Array[Dictionary] = []
	var numbers: Dictionary = result.get("mark_numbers", {})
	for active in Status.marks(combatant.statuses):
		var entry: Dictionary = mark_entry(active)
		if active.bound_intent == intent and bool(result["attacked"]):
			entry["outcome"] = "spent"
			var tally: Dictionary = numbers.get(active.data.intent_mark, {"before": 0, "after": 0})
			entry["before"] = int(tally["before"])
			entry["after"] = int(tally["after"])
		else:
			entry["outcome"] = "lost"
			entry["reason"] = "replaced" if active.bound_intent != intent else "cancelled"
		combatant.statuses.erase(active)
		settled.append(entry)
	return settled

# What the run log and the readout say of a status living on an intent.
static func mark_entry(active: Status) -> Dictionary:
	return {"mark": active.data.intent_mark, "status": active.data.id, "intent": active.bound_intent.intent_name if active.bound_intent != null else "", "granted_by": active.granted_by}

static func is_denied(combatant: Combatant) -> bool:
	return Status.skip_turn_status(combatant.statuses) != null

# Its next action held a turn (Deny's Delayed).
static func is_delayed(combatant: Combatant) -> bool:
	return Status.delay_status(combatant.statuses) != null

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

# The phase's trigger (EnemyData.phase_hp_threshold): the first time this
# living enemy's HP is strictly below that fraction of its max, it gains
# phase_status - once per fight; nothing is cancelled. True only on the
# call that grants it, for the caller to announce.
static func check_phase(combatant: Combatant, data: EnemyData) -> bool:
	if data == null or data.phase_hp_threshold <= 0.0 or data.phase_status == null or combatant.phase_reached or combatant.hp <= 0:
		return false
	if float(combatant.hp) >= float(combatant.max_hp) * data.phase_hp_threshold:
		return false
	combatant.phase_reached = true
	Status.apply_to(combatant.statuses, data.phase_status)
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
# plus this enemy's attack bonus - on every hit (StatusData.attack_
# damage_bonus - Hungry), less the attack-card status on an intent that
# doesn't take it (held_back()) - then its outgoing modifiers and the
# player's incoming ones, so a modifier always reads the bonus in. The
# one number take_turn() lands and preview_intent() shows, hit by hit;
# `player_statuses` is the player's list or the preview's copy of it.
# A strike back (`strike_back`) reads neither side's statuses that wait
# for the enemy's turn (Status.strike_back_view()).
static func hit_amount(combatant: Combatant, data: EnemyData, intent: EnemyIntent, hit: int, player_statuses: Array[Status], strike_back: bool = false) -> int:
	var own: Array[Status] = Status.strike_back_view(combatant.statuses) if strike_back else combatant.statuses
	var theirs: Array[Status] = Status.strike_back_view(player_statuses) if strike_back else player_statuses
	return _hit_amount_seen(combatant, data, intent, own, theirs)

# One hit of `combatant`'s queued attack as it would read without what
# lives on the intent (Braced, Garnished - Status.marks()): its modifiers
# and bonuses only - the hover's "5×3" before what the marks take.
static func unmarked_hit_amount(combatant: Combatant, data: EnemyData, intent: EnemyIntent, player_statuses: Array[Status]) -> int:
	return _hit_amount_seen(combatant, data, intent, Status.without(combatant.statuses, Status.marks(combatant.statuses)), player_statuses)

# hit_amount() off the statuses given for each side.
static func _hit_amount_seen(combatant: Combatant, data: EnemyData, intent: EnemyIntent, own: Array[Status], theirs: Array[Status]) -> int:
	var amount: int = intent_value(combatant, data, intent)
	amount += Status.attack_bonus(own, combatant.is_critical(), held_back(data, intent))
	amount = Status.apply_modifiers(amount, own, StatusData.ModifierTarget.OUTGOING_DAMAGE)
	return Status.apply_modifiers(amount, theirs, StatusData.ModifierTarget.INCOMING_DAMAGE)

# One hit's `before` and `after` a mark, onto its running "before"/"after".
static func _tally_mark(numbers: Dictionary, mark: StringName, before: int, after: int) -> void:
	var tally: Dictionary = numbers.get(mark, {"before": 0, "after": 0})
	tally["before"] = int(tally["before"]) + before
	tally["after"] = int(tally["after"]) + after
	numbers[mark] = tally

# What one hit gives up to the attack's total reduction (Garnished -
# StatusData.reduces_attack_total) with `reduction_left` still to soak:
# all of it up to the hit, so a hit lands 0 at the least and the rest
# passes to the next. Applied to hit_amount(), after every modifier and
# before block - the one rule take_turn() lands and preview_intent()
# shows; each caller carries its own reduction_left across the hits.
static func reduce_hit(amount: int, reduction_left: int) -> int:
	return clampi(reduction_left, 0, maxi(amount, 0))

# Unblocked damage becomes Grace. Accumulates ACROSS the whole enemy
# turn rather than per enemy: the cap is the window's, so two enemies
# hitting for 5 and 8 leave 8 under LARGEST_HIT and 13 under SUM. Called
# by land_attack() and never by anything else; public only so
# battle_controller.gd's tests of the same rule have a seam.
#
# Only reached when damage actually got past block and absorb, and never
# from DamagePipeline.apply_bypass() - which is the whole of self-damage
# and status ticks - so a Bite Down opens nothing without being
# special-cased. Each hit opens only grace_open_fraction of itself, rounded
# down, and the cap scales with it: the largest hit's share, or the share
# of the turn's sum. Returns how much Grace this call added. A strike back
# (counter_strike()) opens it too, in the player's own turn - the window
# then closes at that turn's end, like any other.
# What one attack opens Grace to on its own - the same share open_grace()
# reads: the largest hit's, or its sum's, at grace_open_fraction. 0 for a
# fighter without Grace.
static func grace_share(player: Combatant, largest_hit: int, total_to_hp: int) -> int:
	if not player.has_grace:
		return 0
	var fraction: float = clampf(player.grace_open_fraction, 0.0, 1.0)
	if player.grace_cap_mode == CharacterData.GraceCapMode.SUM:
		return floori(float(total_to_hp) * fraction)
	return floori(float(largest_hit) * fraction)

static func open_grace(player: Combatant, largest_hit: int, total_to_hp: int) -> int:
	if not player.has_grace:
		return 0
	var before: int = player.grace
	var fraction: float = clampf(player.grace_open_fraction, 0.0, 1.0)
	if player.grace_cap_mode == CharacterData.GraceCapMode.SUM:
		player.grace += floori(float(total_to_hp) * fraction)
	else:
		player.grace = maxi(player.grace, floori(float(largest_hit) * fraction))
	if player.grace > before:
		player.grace_turns_left = maxi(player.grace_window_turns, 1)
	return player.grace - before

# What the queued intent says about the enemy, kept in step with it:
# Combatant.buried - under the sand exactly while a BURROW is what comes
# next - and the intent's status_while_queued, held exactly while that
# intent is queued (the Underfoot's Covered, then Exposed): any other
# intent's is taken off first, so the two never overlap.
static func _sync_queued(combatant: Combatant, data: EnemyData) -> void:
	var intent := current_intent(combatant, data)
	combatant.buried = intent != null and intent.type == EnemyIntent.IntentType.BURROW
	var held: StatusData = intent.status_while_queued if intent != null else null
	for queued: StatusData in _queued_statuses(data):
		if queued == held:
			continue
		var active: Status = Status.find_in(combatant.statuses, queued)
		if active != null:
			Status.remove_from(combatant.statuses, active)
	if held != null and Status.find_in(combatant.statuses, held) == null:
		Status.apply_to(combatant.statuses, held)

# Every status_while_queued this enemy's intents carry - its loop's and
# their on_interrupt interjections'.
static func _queued_statuses(data: EnemyData) -> Array[StatusData]:
	var found: Array[StatusData] = []
	for intent: EnemyIntent in data.intents:
		for each: EnemyIntent in [intent, intent.on_interrupt if intent != null else null]:
			if each != null and each.status_while_queued != null and not found.has(each.status_while_queued):
				found.append(each.status_while_queued)
	return found

# Every status_on_resolve this enemy's intents bring - its loop's and
# their on_interrupt interjections': each lasts until the enemy's next
# move. (A DIG's found_status runs for its own duration instead.)
static func _resolved_statuses(data: EnemyData) -> Array[StatusData]:
	var found: Array[StatusData] = []
	for intent: EnemyIntent in data.intents:
		for each: EnemyIntent in [intent, intent.on_interrupt if intent != null else null]:
			if each != null and each.status_on_resolve != null and not found.has(each.status_on_resolve):
				found.append(each.status_on_resolve)
	return found

# --- The dig (EnemyIntent.IntentType.DIG) ---

# A DIG resolving: under the sand, its mound_count mounds standing - each
# its own Combatant of mound_hp HP (mound_guards) - under one of them drawn
# at random: nothing about it is told by where it is. A DIG with no moves
# under or no mounds digs nothing.
static func start_dig(combatant: Combatant, intent: EnemyIntent) -> void:
	if intent == null or intent.under_moves.is_empty() or intent.mound_count <= 0:
		return
	combatant.dug_in = true
	combatant.dig_intent = intent
	combatant.dug_step = 0
	combatant.mounds.clear()
	combatant.mound_guards.clear()
	for mound in intent.mound_count:
		combatant.mounds.append(mound)
		var guard := Combatant.new(maxi(intent.mound_hp, 1))
		guard.mound_owner = combatant
		guard.mound_index = mound
		combatant.mound_guards.append(guard)
	combatant.true_mound = randi_range(0, intent.mound_count - 1)
	# Dug in, on its readout, for as long as it is under (_end_dig()).
	if intent.dug_in_status != null and Status.find_in(combatant.statuses, intent.dug_in_status) == null:
		Status.apply_to(combatant.statuses, intent.dug_in_status)
		var held: Status = Status.find_in(combatant.statuses, intent.dug_in_status)
		if held != null and intent.under_moves[0] != null:
			held.magnitude = intent.under_moves[0].value

# Up out of the sand, its mounds gone; true_mound kept - where it came up.
static func _end_dig(combatant: Combatant) -> void:
	if combatant.dig_intent != null and combatant.dig_intent.dug_in_status != null:
		var held: Status = Status.find_in(combatant.statuses, combatant.dig_intent.dug_in_status)
		if held != null:
			Status.remove_from(combatant.statuses, held)
	combatant.dug_in = false
	combatant.dug_step = 0
	combatant.mounds.clear()

# Whether `guard` - a mound's Combatant (Combatant.mound_owner) - is still
# standing in its row: its enemy under it, the mound not broken or gone.
static func mound_standing(guard: Combatant) -> bool:
	return guard != null and guard.mound_owner != null and guard.mound_owner.dug_in and guard.mound_owner.mounds.has(guard.mound_index) and guard.hp > 0

# Found - its own mound broken: forced up there, the eruption off, its
# DIG's found_status (Exposed) on it for that status's duration; its next
# move is the loop's own. False when it isn't under.
static func unearth(combatant: Combatant, data: EnemyData) -> bool:
	if combatant == null or not combatant.dug_in:
		return false
	var dig: EnemyIntent = combatant.dig_intent
	_end_dig(combatant)
	if dig != null and dig.found_status != null and Status.find_in(combatant.statuses, dig.found_status) == null:
		Status.apply_to(combatant.statuses, dig.found_status)
	_sync_queued(combatant, data)
	return true

# Mound `mound` of `combatant`'s row broken (its Combatant at 0 HP): a
# wrong one is gone and nothing more happens - BROKE_WRONG; its own forces
# it up there, Exposed (unearth()) - BROKE_TRUE. NOT_BROKEN for a mound
# already gone or an enemy not under.
enum MoundBreak { NOT_BROKEN, BROKE_WRONG, BROKE_TRUE }
static func break_mound(combatant: Combatant, data: EnemyData, mound: int) -> MoundBreak:
	if combatant == null or not combatant.dug_in or not combatant.mounds.has(mound):
		return MoundBreak.NOT_BROKEN
	if mound != combatant.true_mound:
		combatant.mounds.erase(mound)
		return MoundBreak.BROKE_WRONG
	unearth(combatant, data)
	return MoundBreak.BROKE_TRUE

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
	_sync_queued(combatant, data)
	return true

# A packmate answering a SIGNAL (BattleController._answer_signal()): one
# attack, out of turn - the first ATTACK in its loop, from where the loop
# stands - landed as its own turn's would be (land_attack(), what it puts
# on the player included). Its loop, its turn count and anything waiting
# for its own turn are left alone. take_turn()'s attack keys; "attacked"
# false when it has no attack to answer with.
static func answer_signal(combatant: Combatant, data: EnemyData, player: Combatant) -> Dictionary:
	var result: Dictionary = {"intent": "", "hits": [], "attacked": false, "damage_to_hp": 0, "grace_opened": 0, "saved_heal": 0, "blocked": 0, "absorbed": 0, "tolled": 0, "applied_to_player": 0}
	var intent: EnemyIntent = signal_answer_intent(combatant, data)
	if intent == null or combatant.hp <= 0 or player.hp <= 0:
		return result
	result["intent"] = intent.intent_name
	# What lives on its own intent (Braced, Garnished on its Nip) waits for
	# that intent's own turn: out of the list while the answer lands, then
	# back where it was.
	var marked: Array[Status] = Status.marks(combatant.statuses)
	var at: Array[int] = []
	for active in marked:
		at.append(combatant.statuses.find(active))
		combatant.statuses.erase(active)
	land_attack(combatant, data, intent, player, result)
	for i in marked.size():
		combatant.statuses.insert(mini(at[i], combatant.statuses.size()), marked[i])
	if intent.applies_to_player != null and intent.applied_amount > 0:
		Status.apply_amount(player.statuses, intent.applies_to_player, intent.applied_amount)
		result["applied_to_player"] = intent.applied_amount
	return result

# The attack a packmate answers a SIGNAL with: the first ATTACK in its
# loop from the intent queued now. Null with none.
static func signal_answer_intent(combatant: Combatant, data: EnemyData) -> EnemyIntent:
	# Delayed (Deny): it holds its own move, and answers nothing.
	if data == null or data.intents.is_empty() or is_delayed(combatant):
		return null
	var count: int = data.intents.size()
	var start: int = clampi(combatant.current_intent_index, 0, count - 1)
	for step in count:
		var intent: EnemyIntent = data.intents[(start + step) % count]
		if intent != null and intent.type == EnemyIntent.IntentType.ATTACK:
			return intent
	return null

# A move only a pack makes - dropped from the loop once the enemy is the
# last of its pack: one marked pack_only (the dragonflies' Swarm), and a
# heal for packmates (HEAL_ALLY - the Nipper's Forage). A simultaneous
# move is only a shared beat, and isn't one by that alone.
static func is_pack_move(intent: EnemyIntent) -> bool:
	return intent != null and (intent.pack_only or intent.type == EnemyIntent.IntentType.HEAL_ALLY)

static func _advance_intent(combatant: Combatant, data: EnemyData) -> void:
	if data.intents.is_empty():
		return
	if data.erratic_intent_selection:
		combatant.previous_intent_index = combatant.current_intent_index
		combatant.current_intent_index = _pick_erratic_intent_index(data, combatant.current_intent_index, combatant.pack_alone)
		return
	# Alone, the cycle steps over its pack moves - at most once round, so
	# a loop of nothing else still queues something.
	for _step in data.intents.size():
		combatant.current_intent_index = (combatant.current_intent_index + 1) % data.intents.size()
		if not combatant.pack_alone or not is_pack_move(data.intents[combatant.current_intent_index]):
			return

# An encounter's exclusion (FloorEnemy.excluded_intent): when the intent
# named `excluded` is this erratic enemy's queued one and any of
# `packmate_intents` (the other living enemies' queued intents) is named
# `trigger`, it draws again without it - the same weighted pick, with
# no_immediate_repeat against the move before (Combatant.previous_
# intent_index) and turn_one_locked on its first, as the draw it
# replaces had. An interjection, a loop enemy, nothing else to draw, or
# no trigger: left as it is. Returns whether the queued intent changed.
static func exclude_queued(combatant: Combatant, data: EnemyData, excluded: String, trigger: String, packmate_intents: Array[EnemyIntent]) -> bool:
	if excluded.is_empty() or trigger.is_empty() or not data.erratic_intent_selection or combatant.interjected_intent != null:
		return false
	var queued: EnemyIntent = current_intent(combatant, data)
	if queued == null or queued.intent_name != excluded:
		return false
	var triggered: bool = false
	for intent in packmate_intents:
		if intent != null and intent.intent_name == trigger:
			triggered = true
	if not triggered:
		return false
	var index: int
	if combatant.turns_taken == 0:
		index = _pick_erratic_initial_index(data, excluded)
	else:
		index = _pick_erratic_intent_index(data, combatant.previous_intent_index, combatant.pack_alone, excluded)
	if index < 0 or data.intents[index].intent_name == excluded:
		return false
	combatant.current_intent_index = index
	_sync_queued(combatant, data)
	return true

# `excluded`: an intent name left out of the draw (exclude_queued()).
static func _pick_erratic_intent_index(data: EnemyData, previous_index: int, pack_alone: bool, excluded: String = "") -> int:
	var weights: Dictionary = {}
	for i in data.intents.size():
		var intent := data.intents[i]
		if i == previous_index and intent.no_immediate_repeat:
			continue
		if pack_alone and is_pack_move(intent):
			continue
		if not excluded.is_empty() and intent.intent_name == excluded:
			continue
		weights[i] = intent.erratic_weight
	return _weighted_pick(weights, previous_index)

# The very first intent an erratic enemy ever shows - also excludes
# turn_one_locked intents (the Sputter's own Scissor/Block), so a fresh
# fight can never open on one of those.
static func _pick_erratic_initial_index(data: EnemyData, excluded: String = "") -> int:
	var weights: Dictionary = {}
	for i in data.intents.size():
		if data.intents[i].turn_one_locked:
			continue
		if not excluded.is_empty() and data.intents[i].intent_name == excluded:
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
