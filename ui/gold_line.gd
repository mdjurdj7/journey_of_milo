extends InkLine
class_name GoldLine

# The field HUD row's gold: a stamped coin (InkGlyph's, the loot
# screen's mark too), the numeral, "GOLD" - after TOLL, before GLASSBONE
# and the keepsake, which hide themselves when empty, so GOLD never moves
# when they come or go (see InkLine for the shape, the style and the
# following). Always shown on the field, 0 included.
#
# A change counts the numeral to the new total, up or down (InkLine.
# count_to()); the floor load shows it at once.
#
# RegionField creates it in _setup_field_hud() and hands it the TOLL
# line (sit_beside()); RunState.gold_changed keeps it current. It goes
# with the field row when BattleOverlay hides that for a fight.

func _init() -> void:
	label_text = "GOLD"
	glyph = InkGlyph.Kind.GOLD
	_value_text = "0"

func _ready() -> void:
	super()
	RunState.gold_changed.connect(set_gold)
	snap_gold(RunState.gold)

# Counts the numeral to `gold` from wherever it shows now.
func set_gold(gold: int) -> void:
	count_to(maxi(gold, 0))

# Shows `gold` at once, no count.
func snap_gold(gold: int) -> void:
	snap_count(maxi(gold, 0))
