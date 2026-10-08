extends InkLine
class_name HPLine

# The field HUD row's HP: "58 / 70 HP" - the numeral at full ink, "/ 70"
# in the smaller grey the HP readout's max uses, no glyph - right after
# the DeckPanel's DECK, before TOLL (see InkLine for the shape, the style
# and the following). Always shown on the field, whatever the hover
# readout under the Wanderer is doing.
#
# RegionField creates it in _setup_field_hud() and hands it the DECK line
# (sit_beside()); RunState.player_hp_changed keeps it current. It goes
# when BattleOverlay hides the field line for a fight (the HPBar's battle
# readout reads HP there) and comes back with it.
#
# A change counts the numeral to the new HP (InkLine.count_to()); the
# max snaps.

# Before the max, as HPBar.battle_max_prefix.
@export var max_prefix: String = " / ":
	set(value):
		max_prefix = value
		_set_max(_max)

var _max: int = 0

func _init() -> void:
	label_text = "HP"
	_value_text = "0"

func _ready() -> void:
	super()
	RunState.player_hp_changed.connect(set_hp)
	snap_hp(RunState.player_hp, RunState.player_max_hp)

# Counts to `current`.
func set_hp(current: int, max_hp: int) -> void:
	_set_max(max_hp)
	count_to(maxi(current, 0))

# Shows `current` at once - the floor load.
func snap_hp(current: int, max_hp: int) -> void:
	_set_max(max_hp)
	snap_count(maxi(current, 0))

func _set_max(max_hp: int) -> void:
	_max = maxi(max_hp, 0)
	_secondary_text = max_prefix + str(_max)
	_relayout()
