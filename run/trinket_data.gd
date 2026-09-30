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
#   heal_on_win_after_loss  HP back after a WON fight in which the
#                        Wanderer actually lost HP - any source, his own
#                        included (RunState.hp_lost_this_combat) - on top
#                        of heal_on_win
#   combat_start_block   Block as each fight opens (BattleController.
#                        setup()) - ordinary Block, gone at the first
#                        turn reset like any other
#   first_card_free      the fight's first card played costs 0 Energy
#                        (Combatant.energy_cost(), spent on the play)
#   critical_entry_block Block the first time each fight the Wanderer
#                        crosses INTO Critical (Combatant.resolve_
#                        critical_entry()) - not for starting there

@export var id: StringName = &""
@export var display_name: String = ""
# One sentence in rules voice, shown on the KEEPSAKE line's hover, in the
# Wanderer's battle reveal and on the offer. A template (Status.fill_
# template()), filled from this trinket's own numbers -
#   {bonus}  combat_start_status's attack_damage_bonus
#   {toll}   combat_start_status's self_loss_toll_bonus
#   {heal}   heal_on_win             {draw}  opening_draw_bonus
#   {loss_heal}  heal_on_win_after_loss
#   {block}  combat_start_block      {critical_block}  critical_entry_block
#   {s}      "s" unless the count token before it is 1
@export_multiline var description: String = ""
# The shortened line for where it's shown small - the "currently held"
# strip on KeepsakeOffer. The same tokens as description. Empty = the
# full description.
@export_multiline var short_description: String = ""
# One quiet line about the object itself, not what it does - shown under
# its name where it's inspected (WorldKeepsake). Empty = no line.
@export_multiline var flavor_text: String = ""
# The object itself, isolated on a transparent background, square - drawn
# large on KeepsakeOffer and small in its held strip, and there for any
# other place that shows the keepsake. Null = no picture; nothing breaks.
@export var art: Texture2D = null
@export var combat_start_status: StatusData = null
@export var heal_on_win: int = 0
@export var opening_draw_bonus: int = 0
@export var heal_on_win_after_loss: int = 0
@export var combat_start_block: int = 0
@export var first_card_free: bool = false
@export var critical_entry_block: int = 0

func describe() -> String:
	return _fill(description)

func describe_short() -> String:
	return _fill(short_description) if not short_description.is_empty() else describe()

func _fill(template: String) -> String:
	var status: StatusData = combat_start_status
	return Status.fill_template(template, {
		"bonus": status.attack_damage_bonus if status != null else 0,
		"toll": status.self_loss_toll_bonus if status != null else 0,
		"heal": heal_on_win,
		"draw": opening_draw_bonus,
		"loss_heal": heal_on_win_after_loss,
		"block": combat_start_block,
		"critical_block": critical_entry_block,
	})

# The fight is opening: this trinket's status, if it has one, onto the
# Wanderer's (fresh, per-fight) statuses.
func apply_combat_start(statuses: Array[Status]) -> void:
	if combat_start_status != null:
		Status.apply_to(statuses, combat_start_status)
