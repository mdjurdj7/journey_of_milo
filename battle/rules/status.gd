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

func _init(status_data: StatusData) -> void:
	data = status_data
	magnitude = status_data.default_magnitude
	turns_remaining = status_data.default_duration_turns
	charges = status_data.default_charges

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

func tick_duration() -> void:
	if turns_remaining > 0:
		turns_remaining -= 1

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
# counter reads its progress after that ("The Return ×2 3/5").
func label() -> String:
	if data == null:
		return ""
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
	var grant: int = data.grants_on_critical.default_charges if data.grants_on_critical != null else 0
	var values: Dictionary = {
		"charges": charges,
		"turns": turns_remaining,
		"stacks": stack_count,
		"percent": absi(magnitude),
		"mark": data.attack_bonus_against_holder,
		"bonus": data.attack_damage_bonus * stack_count,
		"damage": data.countdown_damage,
		"grant": grant,
		"toll": data.self_loss_toll_bonus,
		"progress": progress,
		"count": data.self_loss_trigger_count,
		"drain": trigger_drain(),
		"hp": data.replacement_hp_cost,
		"min_cost": data.replaces_cost_at_least,
		"alone_bonus": data.grants_when_alone.attack_damage_bonus if data.grants_when_alone != null else 0,
		"reduction": data.next_card_cost_reduction * stack_count,
	}
	if holder != null:
		values["survive_hp"] = data.survive_hp(holder.max_hp, holder.critical_hp_fraction)
	return fill_template(data.description, values)

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
		elif values.has(token):
			var value: int = int(values[token])
			last_count = value
			result += str(value)
		else:
			result += match_result.get_string()
	return result + text.substr(cursor)

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
	var existing := find_in(statuses, status_data)
	if existing != null:
		existing.apply_stack()
		return
	statuses.append(Status.new(status_data))

static func find_in(statuses: Array[Status], status_data: StatusData) -> Status:
	for active in statuses:
		if active.data == status_data:
			return active
	return null

static func remove_from(statuses: Array[Status], active: Status) -> void:
	statuses.erase(active)

# Ticks every TICK-category status's own damage (via deal_damage, so the
# caller decides how that damage actually lands - see damage_pipeline.gd's
# apply_bypass(), which is what every real caller passes) and every
# status's own duration, in one pass. Deliberately does NOT remove expired
# statuses - see remove_expired() below, a separate step, so a duration-1
# MODIFIER status can still be read by apply_modifiers() later in the same
# turn before it's erased.
static func tick_all(statuses: Array[Status], deal_damage: Callable) -> void:
	for active in statuses.duplicate():
		if active.data.category == StatusData.Category.TICK and active.magnitude > 0:
			deal_damage.call(active.magnitude)
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
# `critical` says the player isn't. See AttackBonus.
static func attack_bonus(statuses: Array[Status], critical: bool) -> int:
	var total: int = 0
	for active in statuses:
		if active.data == null or active.data.attack_damage_bonus == 0:
			continue
		if active.data.bonus_requires_critical and not critical:
			continue
		total += active.data.attack_damage_bonus * active.stack_count
	return total

# One Attack card has taken its attack bonus (EffectContext.take_attack_
# bonus()): every status whose bonus that paid and that counts charges -
# "+3 on your next Attack" - spends one, and goes at 0. The same gate as
# attack_bonus() above, so a bonus that waits for Critical spends nothing
# while it isn't paid. A status without charges (Dying Light) is never
# touched.
static func spend_attack_bonus_charges(statuses: Array[Status], critical: bool) -> void:
	for active in statuses.duplicate():
		if active.data == null or active.data.attack_damage_bonus == 0 or not active.has_charges():
			continue
		if active.data.bonus_requires_critical and not critical:
			continue
		active.charges -= 1
		if active.charges <= 0:
			statuses.erase(active)

# The cost replacement (StatusData.replaces_cost_at_least - Collateral)
# that would take a card costing `energy_cost` - its Energy after every
# other modifier - or null: one with a charge waiting whose threshold
# the cost reaches. The first such, in the order they were applied.
static func cost_replacement(statuses: Array[Status], energy_cost: int) -> Status:
	for active in statuses:
		if active.data == null or active.data.replaces_cost_at_least <= 0:
			continue
		if not active.has_charges() or active.charges <= 0:
			continue
		if energy_cost >= active.data.replaces_cost_at_least:
			return active
	return null

# A play that cost_replacement() covered has committed: one charge spent,
# and the status gone at 0.
static func spend_cost_replacement(statuses: Array[Status], active: Status) -> void:
	if active == null:
		return
	active.charges -= 1
	if active.charges <= 0:
		statuses.erase(active)

# The Energy every waiting cost reduction (StatusData.next_card_cost_
# reduction - Leverage) takes off the next card: each one's amount per
# stack, summed.
static func cost_reduction(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses:
		if active.data != null and active.data.next_card_cost_reduction > 0:
			total += active.data.next_card_cost_reduction * active.stack_count
	return total

# A play has committed: every waiting cost reduction is spent by it,
# whatever it cost - except one `card` itself applies, which its own
# APPLY_STATUS is about to add to instead (two Leverages, then a card:
# that card gets both).
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

# Its holder just lost HP to their own effect: the extra Toll every
# status that pays for that grants (StatusData.self_loss_toll_bonus),
# each spending a charge when it counts them and going at 0. Called only
# from Combatant.gain_self_loss_toll() - self-inflicted loss, never an
# enemy's hit.
static func take_self_loss_toll_bonus(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses.duplicate():
		if active.data == null or active.data.self_loss_toll_bonus <= 0:
			continue
		total += active.data.self_loss_toll_bonus
		if active.has_charges():
			active.charges -= 1
			if active.charges <= 0:
				statuses.erase(active)
	return total

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

# The extra damage one Attack card would deal the holder of `statuses`
# for every mark on it (StatusData.attack_bonus_against_holder - Come
# Due) with a charge left. Read only: what a card face previews, and what
# spend_mark_bonus() below pays and then spends.
static func mark_bonus(statuses: Array[Status]) -> int:
	var total: int = 0
	for active in statuses:
		if _pays_mark_bonus(active):
			total += active.data.attack_bonus_against_holder
	return total

# One Attack card is landing on the holder of `statuses`: mark_bonus(),
# with each mark that paid it spending one charge and leaving once it has
# none. Called at most once per Attack card per enemy - EffectContext.
# take_mark_bonus() keeps that.
static func spend_mark_bonus(statuses: Array[Status]) -> int:
	var total: int = mark_bonus(statuses)
	for active in statuses.duplicate():
		if not _pays_mark_bonus(active):
			continue
		active.charges -= 1
		if active.charges <= 0:
			statuses.erase(active)
	return total

static func _pays_mark_bonus(active: Status) -> bool:
	return active.data.attack_bonus_against_holder > 0 and active.has_charges() and active.charges > 0

# An enemy's attack against the holder of `statuses` has resolved, every
# hit of it: each status that lasts only until then (StatusData.consumed_
# by_attack_against - No Further, armed) spends a charge, or goes, without them.
static func consume_after_attack_against(statuses: Array[Status]) -> void:
	for active in statuses.duplicate():
		if not active.data.consumed_by_attack_against:
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

# The player just spent Toll - once per card, whatever the amount (see
# EffectContext.spend_toll()): every countdown on `holder` that Toll
# hurries (StatusData.toll_spend_advances) takes a turn off. What reaches
# 0 goes off at the caller's resolve_countdowns().
static func advance_on_toll_spend(holder: Combatant) -> void:
	for active in holder.statuses:
		if active.data != null and active.data.toll_spend_advances and active.has_countdown() and active.turns_remaining > 0:
			active.turns_remaining -= 1

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
	if not holder.is_critical():
		return
	for active in holder.statuses.duplicate():
		if active.data == null or active.data.grants_on_critical == null:
			continue
		holder.statuses.erase(active)
		apply_to(holder.statuses, active.data.grants_on_critical)

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

# Its holder's turn has ended: every status that lasts only that turn
# (StatusData.ends_at_turn_end) is gone.
static func remove_at_turn_end(statuses: Array[Status]) -> void:
	for active in statuses.duplicate():
		if active.data != null and active.data.ends_at_turn_end:
			statuses.erase(active)

# Whether an Attack played now Drains (StatusData.attacks_drain).
static func attacks_drain(statuses: Array[Status]) -> bool:
	for active in statuses:
		if active.data != null and active.data.attacks_drain:
			return true
	return false

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
	player.hp = guard.data.survive_hp(player.max_hp, player.critical_hp_fraction)
	guard.charges -= 1
	if guard.charges <= 0:
		player.statuses.erase(guard)
		if not player.spent_statuses.has(guard.data):
			player.spent_statuses.append(guard.data)
	return true

# The holder's own attack has resolved: every status that lasts only until
# then (StatusData.consumed_by_own_attack - Braced on an enemy) is gone.
static func consume_after_attack(statuses: Array[Status]) -> void:
	for active in statuses.duplicate():
		if active.data.consumed_by_own_attack:
			statuses.erase(active)

# Applies every active MODIFIER-category status matching `target` to
# `amount`, in list order - ADD sums directly; MULTIPLY treats magnitude
# as a PERCENTAGE. Never returns below 0.
static func apply_modifiers(amount: int, statuses: Array[Status], target: StatusData.ModifierTarget) -> int:
	var result := amount
	for active in statuses:
		if active.data.category != StatusData.Category.MODIFIER:
			continue
		if active.data.modifier_target != target:
			continue
		match active.data.modifier_operation:
			StatusData.ModifierOperation.ADD:
				result += active.magnitude
			StatusData.ModifierOperation.MULTIPLY:
				result += roundi(result * active.magnitude / 100.0)
	return max(result, 0)
