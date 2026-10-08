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
# line (sit_beside()); RunState.glassbone_changed keeps it current. It
# goes with the field row when BattleOverlay hides that for a fight.

var _count: int = 0

func _init() -> void:
	label_text = "GLASSBONE"
	glyph = InkGlyph.Kind.GLASSBONE
	_value_text = "0"

func _ready() -> void:
	super()
	RunState.glassbone_changed.connect(set_count)
	set_count(RunState.glassbone)

func set_count(count: int) -> void:
	_count = maxi(count, 0)
	set_value_text(str(_count))

func _is_shown() -> bool:
	return _count > 0
