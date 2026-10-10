extends Resource
class_name EncounterSlot

# One place on a floor where an encounter stands - see FloorData.slots.
# The slot is the where (an anchor, a yaw, whether it gates the exit);
# its options are the what (EncounterOption: who stands there, and the
# props that come with them). One option is chosen per floor load and
# spawned by RegionField (_spawn_floor_enemies(), _spawn_floor_props(),
# _spawn_floor_patrols()); a slot with one option always stands that one.
#
# Everything an option places is in the slot's frame: an XZ offset from
# the anchor, turned by yaw_degrees about the anchor (the same rotation.y
# convention the enemies' own yaw uses), so an option authored once can
# stand in a slot facing any way. to_floor() is that mapping.

# The slot's name on its floor - the run log's, the roll's seed, and what
# a prop watching an encounter names (TroughProp.guard_slot). Unique on
# its floor. It is also the members' FieldEnemy.group when an option has
# more than one of them, so a pack's slot is named as its group was.
@export var slot_id: StringName = &""
# World XZ offset from the floor's spawn (x = X, y = Z), like the old
# FloorEnemy.position. The exit gate and the worn band measure from the
# first required slot's anchor (RegionField._setup_exit_gate()).
@export var position: Vector2 = Vector2.ZERO
# Turns everything an option places about the anchor, degrees, and adds
# to each member's and top-level prop's own yaw.
@export var yaw_degrees: float = 0.0
# Whether this slot's encounter stands between the Wanderer and the gate:
# the floor is cleared (RegionField.floor_cleared, the ExitGate opens)
# once no member of a required slot is left standing. False = an
# optional fight, there to be chosen or walked past.
@export var required: bool = true
@export var options: Array[EncounterOption] = []

# An option's local XZ (the slot's frame) as an offset from the floor's
# spawn. The turn is written out rather than through Vector2.rotated()
# so a slot at yaw 0 adds its offsets exactly - cos 0 and sin 0 are 1 and
# 0, so the migrated floors' positions come back bit-for-bit.
func to_floor(local: Vector2) -> Vector2:
	var angle: float = deg_to_rad(yaw_degrees)
	var c: float = cos(angle)
	var s: float = sin(angle)
	return position + Vector2(local.x * c + local.y * s, -local.x * s + local.y * c)

# The encounter role `option` would be fought as: `role_rule` - always
# BattleController.encounter_role in play - over the same three flags each
# member carries into a fight (BattleController.encounter_member()): this
# slot's required, the member's EnemyData.is_elite, its region-end card
# reward. Handed in rather than named here: naming BattleController would
# tie FloorData to the RunState autoload, which a -s script compiles
# without (RunLogger.fight_start() keeps the same distance).
func role_of(option: EncounterOption, role_rule: Callable) -> String:
	var members: Array[Dictionary] = []
	if option != null:
		for member in option.members:
			if member == null or member.enemy_data == null:
				continue
			members.append({
				"required": required,
				"elite": member.enemy_data.is_elite,
				"region_end": member.card_reward == FloorEnemy.CardReward.TOP_TIER_FIRST,
			})
	return String(role_rule.call(members))

# What is wrong with this slot, or "" when nothing is: an id, at least
# one option, ids unique among its options, and every option fought as
# the same role under `role_rule` (role_of()) - so the slot's reward
# never depends on its roll.
func validate(role_rule: Callable) -> String:
	if slot_id == &"":
		return "a slot has no slot_id"
	if options.is_empty():
		return "slot '%s' has no options" % slot_id
	var ids: Dictionary = {}
	var first_role: String = ""
	for index in options.size():
		var option: EncounterOption = options[index]
		if option == null:
			return "slot '%s': option %d is null" % [slot_id, index]
		if option.option_id == &"":
			return "slot '%s': option %d has no option_id" % [slot_id, index]
		if ids.has(option.option_id):
			return "slot '%s': option id '%s' is used twice" % [slot_id, option.option_id]
		ids[option.option_id] = true
		var role: String = role_of(option, role_rule)
		if index == 0:
			first_role = role
		elif role != first_role:
			return "slot '%s': option '%s' is fought as %s, but '%s' as %s - every option in a slot must share its role" % [slot_id, option.option_id, role, options[0].option_id, first_role]
	return ""

# The option with this id, or null.
func find_option(option_id: StringName) -> EncounterOption:
	for option in options:
		if option != null and option.option_id == option_id:
			return option
	return null
