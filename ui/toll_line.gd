extends InkLine
class_name TollLine

# The field HUD's Toll: "TOLL n" as a line of ink beside the DeckPanel's
# DECK line (see InkLine for the shape, the style and the following).
# Always shown on the field, 0 included.
#
# RegionField creates it in _setup_field_hud() and hands it the DECK line
# (sit_beside()) and the Toll to start on; after that RunState.toll_
# changed keeps it current. It goes when BattleOverlay hides the field
# line for a fight (the HPBar's own Toll block reads Toll there) and
# comes back with it.

func _init() -> void:
	label_text = "TOLL"
	_value_text = "0"

func _ready() -> void:
	super()
	RunState.toll_changed.connect(set_toll)

func set_toll(toll: int) -> void:
	set_value_text(str(maxi(toll, 0)))
