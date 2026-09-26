extends RefCounted
class_name Status

# One status actually affecting one combatant right now - the runtime
# counterpart to StatusData's static definition.

var data: StatusData
var magnitude: int
var turns_remaining: int
var stack_count: int = 1

func _init(status_data: StatusData) -> void:
	data = status_data
	magnitude = status_data.default_magnitude
	turns_remaining = status_data.default_duration_turns

func apply_stack() -> void:
	stack_count += 1
	match data.stack_rule:
		StatusData.StackRule.REFRESH_DURATION:
			turns_remaining = data.default_duration_turns
		StatusData.StackRule.ADD_MAGNITUDE:
			magnitude += data.default_magnitude
		StatusData.StackRule.REFRESH_AND_ADD:
			turns_remaining = data.default_duration_turns
			magnitude += data.default_magnitude
		StatusData.StackRule.IGNORE:
			pass

func tick_duration() -> void:
	if turns_remaining > 0:
		turns_remaining -= 1

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
# and hold a lethal guard, they're left at 1 HP and the guard is spent -
# removed, and recorded when it's once per combat. Returns whether it
# fired.
static func refuse_lethal(player: Combatant, was_critical: bool) -> bool:
	if player.hp > 0:
		return false
	var guard: Status = lethal_guard(player.statuses, was_critical)
	if guard == null:
		return false
	player.hp = 1
	player.statuses.erase(guard)
	if guard.data.once_per_combat:
		player.spent_statuses.append(guard.data)
	return true

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
