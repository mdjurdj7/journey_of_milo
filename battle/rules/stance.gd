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

# Extra damage this stance adds to an Attack, all stacks counted. 0 with
# no stance, which is every fight for a player who hasn't taken one.
static func attack_bonus(stance: Stance) -> int:
	if stance == null or stance.data == null:
		return 0
	return stance.data.attack_damage_bonus * stance.stacks

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
