extends InkLine
class_name GlassboneLine

# The field HUD row's Glassbone: a shard outline, the numeral,
# "GLASSBONE" - after GOLD, the last of the resources, before the
# keepsake's wider gap (see InkLine for the shape, the style and the
# following). Hidden until the run has taken its first piece - the HUD
# doesn't advertise the material before the player has found any - and
# while hidden the keepsake sits beside GOLD instead.
#
# RegionField creates it in _setup_field_hud() and hands it the GOLD
# line (sit_beside()); RunState.glassbone_changed counts it to each new
# total (InkLine.count_to()). It goes with the field row when
# BattleOverlay hides that for a fight.

func _init() -> void:
	label_text = "GLASSBONE"
	glyph = InkGlyph.Kind.GLASSBONE
	_value_text = "0"

func _ready() -> void:
	super()
	RunState.glassbone_changed.connect(set_count)
	snap_count(maxi(RunState.glassbone, 0))

# Counts to `count`; shown from the first piece, whatever the numeral is
# still counting through.
func set_count(count: int) -> void:
	var was_shown: bool = _is_shown()
	count_to(maxi(count, 0))
	if _is_shown() != was_shown:
		_relayout()

func _is_shown() -> bool:
	return _count_target > 0
