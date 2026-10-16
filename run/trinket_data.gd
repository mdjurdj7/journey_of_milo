extends Resource
class_name TrinketData

# One trinket - a keepsake or a worn piece (armor), by its slot. The run
# holds at most one of each (RunState.keepsake, RunState.worn); where one
# comes from is its source's own table (KeepsakeTable - EnemyData.
# keepsake_table, EnemyData.armor_table), never a universal pool, and
# never a card reward. A keepsake has no rarity: a source's weights are
# the only odds there are. A worn piece has one (COMMON or RARE), drawn
# by its elite's armor_rare_chance and shown only in its name's finish.
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
#   first_card_free      the fight's first card played that costs at
#                        least 1 Energy costs 0 (Combatant.energy_cost(),
#                        spent on that play; 0-cost cards pass it by)
#   critical_entry_block Block the first time each fight the Wanderer
#                        crosses INTO Critical (Combatant.resolve_
#                        critical_entry()) - not for starting there
#   end_turn_keep        how many hand cards he may keep at the end of
#                        each of his turns: End Turn opens a choice of 0
#                        to this many first (BattleController.end_turn()),
#                        and the kept ones skip the discard
#   draw_on_multi_hit    cards drawn the first time each of his turns a
#                        card takes HP from two or more enemies (Battle
#                        Controller._resolve_play()) - its kills included
#   max_hp_bonus         max HP while held (RunState.equip_worn()): added
#                        on equip without healing; taken off on removal,
#                        current HP clamped to the new max
#   first_hit_scale      below 1: the first enemy attack hit each fight
#                        that would get past Block is scaled by it,
#                        rounded down, before Block (EnemyTurn.land_
#                        attack()) - Grace opens on what then reaches HP
#   hit_back_damage      damage to an enemy, through its Block, once for
#                        each of its attacks that lands on him
#
# Every hook reads both slots (RunState.held_pieces()), so any field works
# in either; the worn ones are written for armor.

enum Slot { KEEPSAKE, WORN }

@export var id: StringName = &""
@export var display_name: String = ""
# Which of the run's two slots it goes in.
@export var slot: Slot = Slot.KEEPSAKE
# A worn piece's rarity - COMMON or RARE, its name's finish (CardRarity
# Finish, the cards' own). A keepsake leaves it unset and shows none.
@export var rarity: CardData.CardRarity = CardData.CardRarity.UNSET
# One sentence in rules voice, shown on the KEEPSAKE line's hover, in the
# Wanderer's battle reveal and on the offer. A template (Status.fill_
# template()), filled from this trinket's own numbers -
#   {bonus}  combat_start_status's attack_damage_bonus
#   {heal}   heal_on_win             {draw}  opening_draw_bonus
#   {loss_heal}  heal_on_win_after_loss
#   {block}  combat_start_block      {critical_block}  critical_entry_block
#   {keep}   end_turn_keep           {multi_draw}  draw_on_multi_hit
#   {max_hp}  max_hp_bonus           {hit_back}  hit_back_damage
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
# A worn piece lying on the sand (WorldArmor): the scene its body is,
# loaded at runtime - a Meshy model later is a path change. Empty = a
# plain placeholder block.
@export_file("*.tscn", "*.glb") var field_model_path: String = ""
# The world voice's one line when the Wanderer walks up to it lying on the
# sand (WorldArmor). Empty = no line.
@export var drop_line: String = ""
@export var combat_start_status: StatusData = null
@export var heal_on_win: int = 0
@export var opening_draw_bonus: int = 0
@export var heal_on_win_after_loss: int = 0
@export var combat_start_block: int = 0
@export var first_card_free: bool = false
@export var critical_entry_block: int = 0
@export var end_turn_keep: int = 0
@export var draw_on_multi_hit: int = 0
@export var max_hp_bonus: int = 0
@export_range(0.0, 1.0, 0.05) var first_hit_scale: float = 1.0
@export var hit_back_damage: int = 0

func describe() -> String:
	return _fill(description)

func describe_short() -> String:
	return _fill(short_description) if not short_description.is_empty() else describe()

func _fill(template: String) -> String:
	var status: StatusData = combat_start_status
	return Status.fill_template(template, {
		"bonus": status.attack_damage_bonus if status != null else 0,
		"heal": heal_on_win,
		"draw": opening_draw_bonus,
		"loss_heal": heal_on_win_after_loss,
		"block": combat_start_block,
		"critical_block": critical_entry_block,
		"keep": end_turn_keep,
		"multi_draw": draw_on_multi_hit,
		"max_hp": max_hp_bonus,
		"hit_back": hit_back_damage,
	})

# The fight is opening: this trinket's status, if it has one, onto the
# Wanderer's (fresh, per-fight) statuses.
func apply_combat_start(statuses: Array[Status]) -> void:
	if combat_start_status != null:
		Status.apply_to(statuses, combat_start_status)
