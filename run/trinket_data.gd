extends Resource
class_name TrinketData

# One trinket - a keepsake, to the player. The run holds at most one
# (RunState.keepsake); where it comes from is its source's own table
# (KeepsakeTable, on EnemyData.keepsake_table), never a universal pool,
# and never a card reward. No rarity: a source's weights are the only
# odds there are.
#
# What it does is data, read by generic hooks - nothing in combat names a
# trinket:
#   combat_start_status  applied to the Wanderer as each fight opens
#                        (BattleController.setup()), so it shows in his
#                        standing row and hover reveal like any status
#   heal_on_win          HP back after a WON fight - not an escape
#                        (RunState.settle_keepsake_win(), from RegionField)
#   opening_draw_bonus   extra cards in each fight's opening hand
#                        (BattleController.setup()) - a hook, not a
#                        status: the draw that would spend a status is the
#                        fight's first beat, before anyone could read it

@export var id: StringName = &""
@export var display_name: String = ""
# One sentence in rules voice, shown on the KEEPSAKE line's hover, in the
# Wanderer's battle reveal and on the offer. A template (Status.fill_
# template()), filled from this trinket's own numbers -
#   {bonus}  combat_start_status's attack_damage_bonus
#   {toll}   combat_start_status's self_loss_toll_bonus
#   {heal}   heal_on_win             {draw}  opening_draw_bonus
#   {s}      "s" unless the count token before it is 1
@export_multiline var description: String = ""
@export var combat_start_status: StatusData = null
@export var heal_on_win: int = 0
@export var opening_draw_bonus: int = 0

func describe() -> String:
	var status: StatusData = combat_start_status
	return Status.fill_template(description, {
		"bonus": status.attack_damage_bonus if status != null else 0,
		"toll": status.self_loss_toll_bonus if status != null else 0,
		"heal": heal_on_win,
		"draw": opening_draw_bonus,
	})

# The fight is opening: this trinket's status, if it has one, onto the
# Wanderer's (fresh, per-fight) statuses.
func apply_combat_start(statuses: Array[Status]) -> void:
	if combat_start_status != null:
		Status.apply_to(statuses, combat_start_status)
