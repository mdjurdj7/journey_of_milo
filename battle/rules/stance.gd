extends RefCounted
class_name Stance

# One stance actually held, this fight: which StanceData, how many stacks
# of it, and how many of the player's turns are left. Per fight, like the
# Combatant that holds it - leaving or winning discards it with nothing to
# clear, the same way Grace works.
#
# The Combatant holds ONE of these (Combatant.stance). Playing the stance
# already up adds a stack and refreshes the timer; playing a different one
# replaces it outright at one stack. That's a deliberate limit: two
# bargains running at once is a different design, and the hooks below
# would each need to decide how they compose.

var data: StanceData = null
var stacks: int = 1
# Rest of the combat when data.duration_turns is 0 - see its own doc.
var turns_left: int = 0

func _init(stance_data: StanceData) -> void:
	data = stance_data
	stacks = 1
	turns_left = stance_data.duration_turns if stance_data != null else 0

# Takes the stance, or deepens it. Returns the Combatant's stance so a
# caller can report what happened without re-reading it.
static func apply_to(combatant: Combatant, stance_data: StanceData) -> Stance:
	if stance_data == null:
		return combatant.stance
	if combatant.stance != null and combatant.stance.data == stance_data:
		combatant.stance.stacks += 1
		combatant.stance.turns_left = stance_data.duration_turns
	else:
		combatant.stance = Stance.new(stance_data)
	return combatant.stance

# What this stance does right now, in rules voice: StanceData.description
# with its tokens filled from the stacks held (see the token list there;
# Status.fill_template() does the filling).
func describe() -> String:
	if data == null:
		return ""
	return Status.fill_template(data.description, template_values())

# The numbers describe() fills its template with, by token name - also
# what a card face that takes this stance reads (CardView._resolve_tokens()).
func template_values() -> Dictionary:
	return {
		"stacks": stacks,
		"turns": turns_left,
		"bonus": data.attack_damage_bonus * stacks,
		"hp_loss": data.attack_hp_loss * stacks,
	}

# Extra damage this stance adds to an Attack, all stacks counted. 0 with
# no stance, which is every fight for a player who hasn't taken one - and
# 0 when the stance wants Critical and `critical` says the player isn't.
# The whole attack bonus, stance and statuses together, is AttackBonus's.
static func attack_bonus(stance: Stance, critical: bool) -> int:
	return add_attack_bonus(NumberBreakdown.new(), stance, critical).total

# The same, as a part of `into` named for the stance (a card face's
# breakdown of its number - NumberBreakdown); nothing when it pays none.
static func add_attack_bonus(into: NumberBreakdown, stance: Stance, critical: bool) -> NumberBreakdown:
	if stance == null or stance.data == null:
		return into
	if stance.data.bonus_requires_critical and not critical:
		return into
	return into.add(stance.data.display_name, stance.data.attack_damage_bonus * stance.stacks)

# Whether the stance held forbids gaining Block now (Last Resort) - gated
# on Critical as attack_bonus() is: false when the stance wants Critical
# and `critical` says the player isn't. Block already held is never taken.
static func prevents_block_gain(stance: Stance, critical: bool) -> bool:
	if stance == null or stance.data == null or not stance.data.prevents_block_gain:
		return false
	return critical or not stance.data.bonus_requires_critical

# HP playing an Attack costs, all stacks counted.
static func attack_hp_loss(stance: Stance) -> int:
	if stance == null or stance.data == null:
		return 0
	return stance.data.attack_hp_loss * stance.stacks

# One player turn gone. A duration of 0 never expires, so it is checked
# before the decrement rather than relying on the counter never reaching
# zero. Returns true when the stance ended, so the caller can report it.
static func tick(combatant: Combatant) -> bool:
	var stance: Stance = combatant.stance
	if stance == null or stance.data == null or stance.data.duration_turns <= 0:
		return false
	stance.turns_left -= 1
	if stance.turns_left > 0:
		return false
	combatant.stance = null
	return true
