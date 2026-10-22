extends RefCounted
class_name Status

# One status actually affecting one combatant right now - the runtime
# counterpart to StatusData's static definition.

var data: StatusData
var magnitude: int
var turns_remaining: int
var stack_count: int = 1
# See StatusData.default_charges; 0 on a status that doesn't count them.
var charges: int = 0
# See StatusData.self_loss_trigger_count: the losses counted toward the
# next Drain, 0 up to one short of the count. Kept across a stack - a
# second copy joins the count, it doesn't restart it.
var progress: int = 0
# For the run log only: what put it on (RunLogger.current_source() as it
# was made - "card:Ransom" for the card that played it), carried on to
# what it grants at turn start (resolve_turn_start_triggers()). A heal it
# makes is put down to it (attacks_drain_source()).
var granted_by: String = ""
# A status with an intent_mark (Braced, Garnished): the intent it was put
# on - the one its enemy had queued as the card landed. It holds only
# while that is still the intent queued (EnemyTurn.mark_loss()).
var bound_intent: EnemyIntent = null
# A crossing status's (StatusData.crossing_energy/_draw - Dying Light)
# own record: whether its holder was Critical when last judged (-1: not
# yet - the first look only takes the reading), the crossing waiting to
# resolve ("in", "out", or "" for none), whether it waited out an enemy
# turn, and whether this player turn's trigger is spent.
var crossing_was_critical: int = -1
var crossing_pending: String = ""
var crossing_deferred: bool = false
var crossing_spent: bool = false

func _init(status_data: StatusData) -> void:
	data = status_data
	magnitude = status_data.default_magnitude
	turns_remaining = status_data.default_duration_turns
	charges = status_data.default_charges
	granted_by = RunLogger.current_source()

func apply_stack() -> void:
	stack_count += 1
	match data.stack_rule:
		StatusData.StackRule.RESET:
			stack_count = 1
			magnitude = data.default_magnitude
			turns_remaining = data.default_duration_turns
			charges = data.default_charges
		StatusData.StackRule.REFRESH_DURATION:
			turns_remaining = data.default_duration_turns
		StatusData.StackRule.ADD_MAGNITUDE:
			magnitude += data.default_magnitude
		StatusData.StackRule.REFRESH_AND_ADD:
			turns_remaining = data.default_duration_turns
			magnitude += data.default_magnitude
		StatusData.StackRule.IGNORE:
			pass
		StatusData.StackRule.ADD_CHARGES:
			charges += data.default_charges
	if data.max_stacks > 0:
		stack_count = mini(stack_count, data.max_stacks)

func tick_duration() -> void:
	if turns_remaining > 0:
		turns_remaining -= 1

# Whether this status resolves on a Critical crossing (StatusData.
# crossing_energy/_draw - Dying Light).
func is_crossing() -> bool:
	return data != null and (data.crossing_energy > 0 or data.crossing_draw > 0)

# Whether this status counts charges (StatusData.default_charges).
func has_charges() -> bool:
	return data != null and data.default_charges > 0

# Whether this status counts down to going off (StatusData.countdown_
# damage) - its turns_remaining is then the countdown.
func has_countdown() -> bool:
	return data != null and data.countdown_damage > 0

# Whether this status counts its holder's own HP losses toward a Drain
# (StatusData.self_loss_trigger_count).
func has_self_loss_counter() -> bool:
	return data != null and data.self_loss_trigger_count > 0

# What this counter Drains when it goes off: every stack's share, as one
# number.
func trigger_drain() -> int:
	if data == null:
		return 0
	return data.self_loss_trigger_drain * stack_count

# How this status reads in a standing row: its name, then - for a
# countdown - the turns left ("Sentence 4": a count, not a quantity, so no
# ×), or its charges when it counts them - down to "×1", since the last
# one still matters - or its stacks once there is more than one. A
# counter reads its progress after that ("The Return ×2 3/5"). A TICK,
# and a strike back, read their magnitude - the stacks, the hit
# ("Venom 3", "Coiled 5").
func label() -> String:
	if data == null:
		return ""
	if data.category == StatusData.Category.TICK or data.strikes_back_on_attack_card or data.energy_debt:
		return "%s %d" % [data.display_name, magnitude]
	if has_self_loss_counter():
		var title: String = data.display_name
		if stack_count > 1:
			title = "%s ×%d" % [title, stack_count]
		return "%s %d/%d" % [title, progress, data.self_loss_trigger_count]
	if has_countdown():
		return "%s %d" % [data.display_name, turns_remaining]
	if has_charges():
		return "%s ×%d" % [data.display_name, charges]
	if stack_count > 1:
		return "%s ×%d" % [data.display_name, stack_count]
	return data.display_name

# What this status does right now, in rules voice: StatusData.description
# with its tokens filled from this instance's live numbers (see the token
# list on StatusData.description). Read by the battle readouts' reveal.
# `holder`, when given, fills what depends on who holds it - a lethal
# guard's {survive_hp}.
func describe(holder: Combatant = null) -> String:
	if data == null:
		return ""
	return fill_template(data.description, template_values(holder))

# The numbers describe() fills its template with, by token name - also
# what a card face that applies this status reads for the tokens its own
# don't cover (CardView._resolve_tokens()).
func template_values(holder: Combatant = null) -> Dictionary:
	if data == null:
		return {}
	var grant: int = data.grants_on_critical.default_charges if data.grants_on_critical != null else 0
	var values: Dictionary = {
		"charges": charges,
		"turns": turns_remaining,
		"stacks": stack_count,
		"percent": absi(magnitude),
		"value": magnitude,
		"bonus": data.attack_damage_bonus * stack_count,
		"bonus_each": data.attack_damage_bonus,
		"max": data.attack_damage_bonus * data.max_stacks,
		"damage": data.countdown_damage,
		"grant": grant,
		"progress": progress,
		"count": data.self_loss_trigger_count,
		"drain": trigger_drain(),
		"hp": data.hp_per_missing_energy,
		"alone_bonus": data.grants_when_alone.attack_damage_bonus if data.grants_when_alone != null else 0,
		"reduction": data.next_card_cost_reduction * stack_count,
		"block": data.turn_start_block * stack_count,
		"energy": data.crossing_energy,
		"draw": data.crossing_draw,
		"decay": data.tick_decay,
		"times": times_word(1.0 + magnitude / 100.0),
		"critical_percent": data.raises_critical_percent,
		"barbed": data.barbed_damage,
	}
	if holder != null:
		values["survive_hp"] = data.survive_hp(holder.max_hp, holder.critical_fraction())
	# {share}: the share of damage an Attack heals - this status's, or the
	# one it gives way to at turn start (Ransom's waiting status says its
	# live one's). Left standing on a status with none.
	var heal_fraction: float = data.ransom_heal_fraction
	if heal_fraction <= 0.0 and data.grants_on_turn_start != null:
		heal_fraction = data.grants_on_turn_start.ransom_heal_fraction
	if heal_fraction > 0.0:
		values["share"] = share_word(heal_fraction)
	return values

# Replaces each {token} in `text` with its value from `values`, and each
# {s} with "s" unless the nearest count token before it is 1 - so a
# template's noun follows its number ("1 Attack", "2 Attacks"). A token
# with no value is left standing, the way a card's is, so a mis-authored
# template reads as wrong rather than quietly printing 0. Shared with
# Stance.describe().
static func fill_template(text: String, values: Dictionary) -> String:
	var regex := RegEx.new()
	regex.compile("\\{(\\w+)\\}")
	var result: String = ""
	var last_count: int = 0
	var cursor: int = 0
	for match_result: RegExMatch in regex.search_all(text):
		result += text.substr(cursor, match_result.get_start() - cursor)
		cursor = match_result.get_end()
		var token: String = match_result.get_string(1)
		if token == "s":
			result += "" if last_count == 1 else "s"
		elif values.has(token) and values[token] is String:
			# A word (times_word(), an ordinal): written as it is, and no
			# count for a following {s}.
			result += values[token] as String
		elif values.has(token):
			var value: int = int(values[token])
			last_count = value
			result += str(value)
		else:
			result += match_result.get_string()
	return result + text.substr(cursor)

# A damage multiplier in words, for rules text: "double", "triple", or
# "N×" ("1.5×") for anything else.
static func times_word(multiplier: float) -> String:
	if is_equal_approx(multiplier, 2.0):
		return "double"
	if is_equal_approx(multiplier, 3.0):
		return "triple"
	return "%s×" % String.num(snappedf(multiplier, 0.01))

# A share of something in words, for rules text before "the": "half", or
# "N% of".
static func share_word(fraction: float) -> String:
	if is_equal_approx(fraction, 0.5):
		return "half"
	return "%d%% of" % roundi(fraction * 100.0)

# A count as an ordinal word, for rules text: "first" to "tenth", "Nth"
# past that.
static func ordinal_word(n: int) -> String:
	var words: Array[String] = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
	if n >= 1 and n <= words.size():
		return words[n - 1]
	return "%dth" % n

# What the statuses an Attack card spends (Bent Nail's doubling) add to
# one blow of `blow` among the holder's outgoing modifiers - before the
# enemy's own modifiers and Block. 0 with none up.
static func attack_card_extra(blow: int, statuses: Array[Status]) -> int:
	var with_all: int = apply_modifiers(blow, statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE)
	var without: int = apply_modifiers(blow, statuses, StatusData.ModifierTarget.OUTGOING_DAMAGE, true)
	return maxi(with_all - without, 0)

# An Attack card has finished resolving (EffectResolver.resolve_card()):
# every status that StatusData.spent_by_attack_card spends one charge,
# and goes at 0 - Bent Nail's doubling, once its Attack is done. Returns
# the ids of those that were up, for the run log.
static func spend_on_attack_card(statuses: Array[Status]) -> Array[String]:
	var spent: Array[String] = []
	for active in statuses.duplicate():
		if active.data == null or not active.data.spent_by_attack_card:
			continue
		spent.append(active.data.id)
		active.charges -= 1
		if active.charges <= 0:
			statuses.erase(active)
	return spent

func is_expired() -> bool:
	if turns_remaining == StatusData.DURATION_UNTIL_REMOVED or turns_remaining == StatusData.DURATION_UNTIL_TRIGGERED:
		return false
	return turns_remaining <= 0

# --- Collection-level operations ---
#
# Every caller in this project just wants "the list of Status currently
# active on one combatant" (Combatant.statuses), so these take that Array
# directly rather than wrapping it in its own class.

static func apply_to(statuses: Array[Status], status_data: StatusData) -> void:
	# Each its own (Sentence): never a restack.
	if status_data.stack_rule == StatusData.StackRule.SEPARATE:
		statuses.append(Status.new(status_data))
		return
	var existing := find_in(statuses, status_data)
	if existing != null:
		existing.apply_stack()
		return
	statuses.append(Status.new(status_data))

# Applies `status_data` carrying `amount` (the Adder's Bite: Venom 3): a
# fresh copy starts at it, and one already up adds it to its magnitude -
# whatever its stack rule does with default_magnitude. The rest of a
# restack (stack_count, duration) is apply_stack()'s, as ever.
static func apply_amount(statuses: Array[Status], status_data: StatusData, amount: int) -> void:
	var existing := find_in(statuses, status_data)
	if existing != null:
		var before: int = existing.magnitude
		existing.apply_stack()
		existing.magnitude = before + amount
		return
	var fresh := Status.new(status_data)
	fresh.magnitude = amount
	statuses.append(fresh)

# The statuses living on an intent (StatusData.intent_mark), in order.
static func marks(statuses: Array[Status]) -> Array[Status]:
	var found: Array[Status] = []
	for active in statuses:
		if active.data != null and active.data.intent_mark != &"":
			found.append(active)
	return found

# The one carrying `mark` ("brace", "garnish"), or null.
static func find_mark(statuses: Array[Status], mark: StringName) -> Status:
	for active in statuses:
		if active.data != null and active.data.intent_mark == mark:
			return active
	return null

# A copy of every status in `statuses`, field for field: what a preview
# spends a charge of or removes (EnemyTurn.turn_state()) leaves the real
# ones untouched.
static func clones(statuses: Array[Status]) -> Array[Status]:
	var copies: Array[Status] = []
	for active in statuses:
		var copy := Status.new(active.data)
		copy.magnitude = active.magnitude
		copy.turns_remaining = active.turns_remaining
		copy.stack_count = active.stack_count
		copy.charges = active.charges
		copy.progress = active.progress
		copy.granted_by = active.granted_by
		copy.bound_intent = active.bound_intent
		copies.append(copy)
	return copies

# `statuses` less `left_out`: a new list, the statuses themselves the same.
static func without(statuses: Array[Status], left_out: Array[Status]) -> Array[Status]:
	var kept: Array[Status] = []
	for active in statuses:
		if not left_out.has(active):
			kept.append(active)
	return kept

static func find_in(statuses: Array[Status], status_data: StatusData) -> Status:
	for active in statuses:
		if active.data == status_data:
			return active
	return null

# The Block `statuses` give at the start of a turn (StatusData.turn_start_
# block per stack - Marrow), summed.
static func turn_start_block(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses:
		if active.data != null and active.data.turn_start_block > 0:
			total += active.data.turn_start_block * active.stack_count
	return total

# The highest Critical line `statuses` raise their holder's to (StatusData.
# raises_critical_percent - Gone Under), as a fraction of max HP; 0 with
# none. Combatant.critical_fraction() takes it over the holder's own.
static func raised_critical_fraction(statuses: Array[Status]) -> float:
	var highest: int = 0
	for active in statuses:
		if active.data != null:
			highest = maxi(highest, active.data.raises_critical_percent)
	return clampf(highest / 100.0, 0.0, 1.0)

# The status that holds its holder's next action a turn (StatusData.
# delays_next_action - Deny's Delayed), or null.
static func delay_status(statuses: Array[Status]) -> Status:
	for active in statuses:
		if active.data != null and active.data.delays_next_action:
			return active
	return null

# The status that skips its holder's next turn (StatusData.skips_next_
# turn - Stunned), or null.
static func skip_turn_status(statuses: Array[Status]) -> Status:
	for active in statuses:
		if active.data != null and active.data.skips_next_turn:
			return active
	return null

# The extra hits `statuses` give a multi-hit attack (StatusData.bonus_
# hits - Off the rock), summed.
static func bonus_hits(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses:
		if active.data != null:
			total += active.data.bonus_hits
	return total

# What `statuses` add to their holder's interrupt thresholds (StatusData.
# interrupt_threshold_change - Off the rock), summed.
static func interrupt_threshold_change(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses:
		if active.data != null:
			total += active.data.interrupt_threshold_change
	return total

# How many times `statuses` have their holder carry out its intent this
# turn (StatusData.repeats_intent - Bereft): the most any of them asks,
# at least 1.
static func intent_repeats(statuses: Array[Status]) -> int:
	var repeats: int = 1
	for active in statuses:
		if active.data != null:
			repeats = maxi(repeats, active.data.repeats_intent)
	return repeats

# What `statuses` take off their holder's next ATTACK in all (StatusData.
# reduces_attack_total - Garnished), summed.
static func attack_total_reduction(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses:
		if active.data != null and active.data.reduces_attack_total:
			total += maxi(active.magnitude, 0)
	return total

static func remove_from(statuses: Array[Status], active: Status) -> void:
	statuses.erase(active)

# Ticks every TICK-category status's own damage (via deal_damage, so the
# caller decides how that damage actually lands - see damage_pipeline.gd's
# apply_bypass(), which is what every real caller passes) and every
# status's own duration, in one pass. Deliberately does NOT remove expired
# statuses - see remove_expired() below, a separate step, so a duration-1
# MODIFIER status can still be read by apply_modifiers() later in the same
# turn before it's erased.
# `deal_damage` is called (amount, the Status ticking) for each tick.
# A TICK that decays (StatusData.tick_decay - Venom) loses that much
# magnitude once it has dealt it, and is gone at 0 - here, since it has
# no duration to run out.
static func tick_all(statuses: Array[Status], deal_damage: Callable) -> void:
	for active in statuses.duplicate():
		if active.data.category == StatusData.Category.TICK and active.magnitude > 0:
			deal_damage.call(active.magnitude, active)
			if active.data.tick_decay > 0:
				active.magnitude -= active.data.tick_decay
				if active.magnitude <= 0:
					statuses.erase(active)
					continue
		active.tick_duration()

static func remove_expired(statuses: Array[Status]) -> void:
	for active in statuses.duplicate():
		if active.is_expired():
			statuses.erase(active)

# clears_on_trigger, made real - see StatusData's own doc. Removes every
# currently-active status with this flag set, unconditionally, regardless
# of what the trigger actually was for the caller.
static func consume_triggered(statuses: Array[Status]) -> void:
	for active in statuses.duplicate():
		if active.data.clears_on_trigger:
			statuses.erase(active)

# The attack bonus every status on `statuses` grants one Attack card -
# attack_damage_bonus per stack, skipping the ones that want Critical when
# `critical` says the player isn't. See AttackBonus. `skip`, when given,
# pays nothing this time (an enemy's attack-card status on an intent that
# doesn't take it - EnemyTurn.hit_amount()). `ongoing_only` leaves out
# every status that counts charges (Keen's "+3 on your next Attack"): a
# one-shot that the card's first hit has already had - what a repeated
# hit gets (EffectContext.take_repeat_attack_bonus()).
static func attack_bonus(statuses: Array[Status], critical: bool, skip: StatusData = null, ongoing_only: bool = false) -> int:
	var total: int = 0
	for active in statuses:
		if active.data == null or active.data.attack_damage_bonus == 0:
			continue
		if skip != null and active.data == skip:
			continue
		if ongoing_only and active.has_charges():
			continue
		if active.data.bonus_requires_critical and not critical:
			continue
		total += active.data.attack_damage_bonus * active.stack_count
	return total

# One Attack card has taken its attack bonus (EffectContext.take_attack_
# bonus()): every status whose bonus that paid and that counts charges -
# "+3 on your next Attack" - spends one, and goes at 0. The same gate as
# attack_bonus() above, so a bonus that waits for Critical spends nothing
# while it isn't paid. A status without charges is never touched.
static func spend_attack_bonus_charges(statuses: Array[Status], critical: bool) -> void:
	for active in statuses.duplicate():
		if active.data == null or active.data.attack_damage_bonus == 0 or not active.has_charges():
			continue
		if active.data.bonus_requires_critical and not critical:
			continue
		active.charges -= 1
		if active.charges <= 0:
			statuses.erase(active)

# The status letting Energy short be paid in HP this turn (StatusData.
# hp_per_missing_energy - Collateral), or null - the cheapest, when
# Collateral and Collateral+ are both up.
static func missing_energy_status(statuses: Array[Status]) -> Status:
	var best: Status = null
	for active in statuses:
		if active.data == null or active.data.hp_per_missing_energy <= 0:
			continue
		if best == null or active.data.hp_per_missing_energy < best.data.hp_per_missing_energy:
			best = active
	return best

# The Energy every waiting cost reduction (StatusData.next_card_cost_
# reduction - Leverage) takes off the next card: each one's amount per
# stack, summed.
static func cost_reduction(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses:
		if active.data != null and active.data.next_card_cost_reduction > 0:
			total += active.data.next_card_cost_reduction * active.stack_count
	return total

# A play of a card costing at least 1 Energy has committed (BattleController
# asks Combatant.takes_next_card_discount() first - a 0-cost card spends
# nothing): every waiting cost reduction is spent by it - except one
# `card` itself applies, which its own APPLY_STATUS is about to add to
# instead (two Leverages, then a card: that card gets both).
static func spend_cost_reduction(statuses: Array[Status], card: CardData) -> void:
	for active in statuses.duplicate():
		if active.data == null or active.data.next_card_cost_reduction <= 0:
			continue
		if _card_applies(card, active.data):
			continue
		statuses.erase(active)

static func _card_applies(card: CardData, status_data: StatusData) -> bool:
	if card == null:
		return false
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.APPLY_STATUS and effect.status_data == status_data:
			return true
	return false

# Its holder just lost HP to their own effect - once per loss, however
# much it took: every counter (StatusData.self_loss_trigger_count) moves
# on one, and each that reaches its count starts again and hands over its
# Drain. Returns the Drain now due, summed - for the caller to resolve
# once there are enemies to hit (EffectContext.resolve_pending_drain()).
# Called only from Combatant.gain_self_loss_toll().
static func count_self_loss(statuses: Array[Status]) -> int:
	var due: int = 0
	for active in statuses:
		if not active.has_self_loss_counter():
			continue
		active.progress += 1
		if active.progress >= active.data.self_loss_trigger_count:
			active.progress = 0
			due += active.trigger_drain()
	return due

# The Energy `statuses` take off the next turn's refill (StatusData.
# energy_debt - Come Due's Owed): each one's magnitude, summed.
static func energy_debt(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses:
		if active.data != null and active.data.energy_debt:
			total += maxi(active.magnitude, 0)
	return total

# An enemy's attack against the holder of `statuses` has resolved, every
# hit of it: each status that lasts only until then (StatusData.consumed_
# by_attack_against - No Further, armed) spends a charge, or goes, without them.
static func consume_after_attack_against(statuses: Array[Status], strike_back: bool = false) -> void:
	for active in statuses.duplicate():
		if not active.data.consumed_by_attack_against:
			continue
		# A strike back passes it by (StatusData.ignores_strike_backs).
		if strike_back and active.data.ignores_strike_backs:
			continue
		if active.has_charges():
			active.charges -= 1
			if active.charges > 0:
				continue
		statuses.erase(active)

# Every countdown on `holder` that has run out (StatusData.countdown_
# damage, turns_remaining at 0) goes off: removed, then its damage dealt
# to the holder through its incoming modifiers and the damage pipeline
# (block, absorb, HP) - never as an Attack. Returns the HP it took, for
# the caller to report.
static func resolve_countdowns(holder: Combatant) -> int:
	var taken: int = 0
	for active in holder.statuses.duplicate():
		if not active.has_countdown() or active.turns_remaining > 0:
			continue
		holder.statuses.erase(active)
		var amount: int = apply_modifiers(active.data.countdown_damage, holder.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)
		taken += DamagePipeline.resolve(amount, holder)["damage_to_hp"]
	return taken

# The player just spent Toll - once per card or replay that spent any,
# whatever the amount (see EffectContext.spend_toll()): every countdown on
# `holder` that Toll hurries (StatusData.toll_spend_advances) takes a turn
# off, each Sentence its own. What reaches 0 goes off at the caller's
# resolve_countdowns(), mid-turn.
# Returns the turns each one left it with, for the run log.
static func advance_on_toll_spend(holder: Combatant) -> Array[int]:
	var left: Array[int] = []
	for active in holder.statuses:
		if active.data != null and active.data.toll_spend_advances and active.has_countdown() and active.turns_remaining > 0:
			active.turns_remaining -= 1
			left.append(active.turns_remaining)
	return left

# Every status waiting for its holder to be Critical (StatusData.grants_
# on_critical - No Further) gives way, if `holder` is Critical now: removed,
# and what it grants applied in its place. Called after each action that
# can take HP - an enemy's attack, a card, the turn's ticks - so the
# action that crossed the line is never softened by the grant. The
# keepsake's Critical-entry Block is judged at the same beat (Combatant.
# resolve_critical_entry()), and needs to see the holder OUT of Critical
# too, so it goes before the early return.
static func resolve_critical_triggers(holder: Combatant) -> void:
	if holder == null:
		return
	holder.resolve_critical_entry()
	_note_crossings(holder)
	if not holder.is_critical():
		return
	for active in holder.statuses.duplicate():
		if active.data == null or active.data.grants_on_critical == null:
			continue
		holder.statuses.erase(active)
		apply_to(holder.statuses, active.data.grants_on_critical)

# Each crossing status (Dying Light) on `holder` takes its reading: a
# change since its last one is a crossing - kept to resolve unless one
# already waits or this turn's is spent.
static func _note_crossings(holder: Combatant) -> void:
	var critical: int = 1 if holder.is_critical() else 0
	for active in holder.statuses:
		if not active.is_crossing():
			continue
		if active.crossing_was_critical >= 0 and critical != active.crossing_was_critical and active.crossing_pending.is_empty() and not active.crossing_spent:
			active.crossing_pending = "in" if critical == 1 else "out"
		active.crossing_was_critical = critical

# The crossing statuses on `statuses` (Dying Light).
static func crossings(statuses: Array[Status]) -> Array[Status]:
	var found: Array[Status] = []
	for active in statuses:
		if active.is_crossing():
			found.append(active)
	return found

# Its holder - an enemy - has just become the last of its pack
# (EnemyTurn.leave_pack()): every status waiting for that (StatusData.
# grants_when_alone - Fed) is removed and its grant applied in its place.
# True when anything changed, for the readout to catch up.
static func resolve_alone_triggers(holder: Combatant) -> bool:
	if holder == null:
		return false
	var changed: bool = false
	for active in holder.statuses.duplicate():
		if active.data == null or active.data.grants_when_alone == null:
			continue
		holder.statuses.erase(active)
		apply_to(holder.statuses, active.data.grants_when_alone)
		changed = true
	return changed

# Its holder's turn has started: every status waiting for that
# (StatusData.grants_on_turn_start - Ransom) is removed and its grant
# applied in its place.
static func resolve_turn_start_triggers(statuses: Array[Status]) -> void:
	for active in statuses.duplicate():
		if active.data == null or active.data.grants_on_turn_start == null:
			continue
		statuses.erase(active)
		apply_to(statuses, active.data.grants_on_turn_start)
		var granted := find_in(statuses, active.data.grants_on_turn_start)
		if granted != null:
			granted.granted_by = active.granted_by

# Its holder's turn has ended: every status that lasts only that turn
# (StatusData.ends_at_turn_end) is gone.
static func remove_at_turn_end(statuses: Array[Status]) -> void:
	for active in statuses.duplicate():
		if active.data != null and active.data.ends_at_turn_end:
			statuses.erase(active)

# Its holder's turn has ended: if a status owes them another turn
# (StatusData.grants_extra_turn - Owed Time), one charge is spent, the
# last removing it, and true - the enemies don't act before it.
static func take_extra_turn(statuses: Array[Status]) -> bool:
	for active in statuses:
		if active.data == null or not active.data.grants_extra_turn:
			continue
		active.charges -= 1
		if active.charges <= 0:
			statuses.erase(active)
		return true
	return false

# The status that has damage past Block take its holder's Toll first
# (StatusData.toll_pays_damage - Thick Skin), or null.
static func toll_payer(statuses: Array[Status]) -> Status:
	for active in statuses:
		if active.data != null and active.data.toll_pays_damage:
			return active
	return null

# Whether an Attack played now Drains (StatusData.attacks_drain).
static func attacks_drain(statuses: Array[Status]) -> bool:
	for active in statuses:
		if active.data != null and active.data.attacks_drain:
			return true
	return false

# What the run log puts an Attack's Drain heal down to: the granted_by of
# the status giving the largest share (attacks_drain_fraction()) - the
# card that played Ransom - else "status:<its id>". "" when none Drains.
static func attacks_drain_source(statuses: Array[Status]) -> String:
	var best: Status = null
	for active in statuses:
		if active.data != null and active.data.attacks_drain and (best == null or active.data.ransom_heal_fraction > best.data.ransom_heal_fraction):
			best = active
	if best == null:
		return ""
	return best.granted_by if not best.granted_by.is_empty() else "status:" + best.data.id

# The share of its HP dealt an Attack played now heals - the largest
# ransom_heal_fraction among the statuses making it Drain; 0 when none is.
static func attacks_drain_fraction(statuses: Array[Status]) -> float:
	var fraction: float = 0.0
	for active in statuses:
		if active.data != null and active.data.attacks_drain:
			fraction = maxf(fraction, active.data.ransom_heal_fraction)
	return fraction

# The status that would stop a lethal enemy hit on a player who was
# `was_critical` before it, or null.
static func lethal_guard(statuses: Array[Status], was_critical: bool) -> Status:
	if not was_critical:
		return null
	for active in statuses:
		if active.data != null and active.data.prevents_lethal_while_critical:
			return active
	return null

# An enemy hit just took `player` to 0 HP. If they were Critical before it
# and hold a lethal guard, they're left at its survive HP (StatusData.
# survive_hp()) and one of its charges is spent - one per copy played. The
# last charge removes it, recorded once in spent_statuses for the
# readout. Returns whether it fired.
static func refuse_lethal(player: Combatant, was_critical: bool) -> bool:
	if player.hp > 0:
		return false
	var guard: Status = lethal_guard(player.statuses, was_critical)
	if guard == null:
		return false
	player.hp = guard.data.survive_hp(player.max_hp, player.critical_fraction())
	guard.charges -= 1
	if guard.charges <= 0:
		player.statuses.erase(guard)
		if not player.spent_statuses.has(guard.data):
			player.spent_statuses.append(guard.data)
	return true

# The holder's own attack has resolved: every status that lasts only until
# then (StatusData.consumed_by_own_attack - Roused, Goaded) is gone - but
# `keep`, which this attack didn't take (EnemyTurn.take_turn()). One living
# on the intent (StatusData.intent_mark - Braced, Garnished) stays: its
# intent settles it once every action of it is done.
static func consume_after_attack(statuses: Array[Status], keep: StatusData = null, strike_back: bool = false) -> void:
	for active in statuses.duplicate():
		if strike_back and active.data.ignores_strike_backs:
			continue
		if active.data.intent_mark != &"":
			continue
		if active.data.consumed_by_own_attack and not (keep != null and active.data == keep):
			statuses.erase(active)

# `statuses` less those a strike back passes by (StatusData.ignores_strike_
# backs - Braced, Garnished, No Further's armed, Unbroken's): what such a
# hit reads its modifiers and reductions off. A new list; the statuses themselves are the same.
static func strike_back_view(statuses: Array[Status]) -> Array[Status]:
	var seen: Array[Status] = []
	for active in statuses:
		if not active.data.ignores_strike_backs:
			seen.append(active)
	return seen

# Applies every active MODIFIER-category status matching `target` to
# `amount`, in list order - ADD sums directly; MULTIPLY treats magnitude
# as a PERCENTAGE. Never returns below 0.
static func apply_modifiers(amount: int, statuses: Array[Status], target: StatusData.ModifierTarget, skip_attack_card_spent: bool = false) -> int:
	var result := amount
	for active in statuses:
		if active.data.category != StatusData.Category.MODIFIER:
			continue
		if active.data.modifier_target != target:
			continue
		# Leaving out what an Attack card spends (Bent Nail's doubling) -
		# for the run log's measure of what that added (attack_card_
		# extra()), never for a blow that lands.
		if skip_attack_card_spent and active.data.spent_by_attack_card:
			continue
		match active.data.modifier_operation:
			StatusData.ModifierOperation.ADD:
				result += active.magnitude
			StatusData.ModifierOperation.MULTIPLY:
				result += roundi(result * active.magnitude / 100.0)
	return max(result, 0)
