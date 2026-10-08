extends InkLine
class_name HPLine

# The field HUD's HP: "HP 58/70" as a line of ink right after the
# DeckPanel's DECK line, before TOLL (see InkLine for the shape, the
# style and the following). Always shown on the field, whatever the
# hover readout under the Wanderer is doing.
#
# RegionField creates it in _setup_field_hud() and hands it the DECK line
# (sit_beside()); RunState.player_hp_changed keeps it current. It goes
# when BattleOverlay hides the field line for a fight (the HPBar's battle
# readout reads HP there) and comes back with it.

func _init() -> void:
	label_text = "HP"
	_value_text = "0/0"

func _ready() -> void:
	super()
	RunState.player_hp_changed.connect(set_hp)
	set_hp(RunState.player_hp, RunState.player_max_hp)

func set_hp(current: int, max_hp: int) -> void:
	set_value_text("%d/%d" % [maxi(current, 0), maxi(max_hp, 0)])
