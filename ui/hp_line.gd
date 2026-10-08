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

# Before the max, as HPBar.battle_max_prefix.
@export var max_prefix: String = " / ":
	set(value):
		max_prefix = value
		set_hp(_current, _max)

var _current: int = 0
var _max: int = 0

func _init() -> void:
	label_text = "HP"
	_value_text = "0"

func _ready() -> void:
	super()
	RunState.player_hp_changed.connect(set_hp)
	set_hp(RunState.player_hp, RunState.player_max_hp)

func set_hp(current: int, max_hp: int) -> void:
	_current = maxi(current, 0)
	_max = maxi(max_hp, 0)
	_secondary_text = max_prefix + str(_max)
	set_value_text(str(_current))
