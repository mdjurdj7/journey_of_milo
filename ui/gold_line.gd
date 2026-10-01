extends InkLine
class_name GoldLine

# The field HUD's gold: "GOLD n" as a line of ink at the end of the row,
# after GLASSBONE (see InkLine for the shape, the style and the following;
# with GLASSBONE or KEEPSAKE hidden it sits beside whatever is shown).
# Always shown on the field, 0 included.
#
# A change counts the numeral up (or down) to the new total over
# count_up_time rather than jumping - it lands on the exact total. The
# line's own tween, pause-proof, so it runs while the reward screen holds
# the field frozen (InkLine runs ALWAYS).
#
# RegionField creates it in _setup_field_hud() and hands it the GLASSBONE
# line (sit_beside()); RunState.gold_changed keeps it current. It goes
# with the field row when BattleOverlay hides that for a fight.

# Seconds for the numeral to count to a new total. Read as each count
# starts, so a Remote-tab edit takes effect on the next change.
@export var count_up_time: float = 0.5

var _target: int = 0
var _shown: float = 0.0
var _count_tween: Tween = null

func _init() -> void:
	label_text = "GOLD"
	_value_text = "0"

func _ready() -> void:
	super()
	RunState.gold_changed.connect(set_gold)
	snap_gold(RunState.gold)

# Counts the numeral to `gold` from wherever it shows now.
func set_gold(gold: int) -> void:
	_target = maxi(gold, 0)
	if _count_tween != null:
		_count_tween.kill()
	if count_up_time <= 0.0 or not is_inside_tree():
		snap_gold(_target)
		return
	_count_tween = create_tween()
	_count_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_count_tween.tween_method(_set_shown, _shown, float(_target), count_up_time)
	# Lands on the exact total, whatever the last step's rounding.
	_count_tween.tween_callback(_set_shown.bind(float(_target)))

# Shows `gold` at once, no count.
func snap_gold(gold: int) -> void:
	if _count_tween != null:
		_count_tween.kill()
		_count_tween = null
	_target = maxi(gold, 0)
	_set_shown(float(_target))

func _set_shown(value: float) -> void:
	_shown = value
	set_value_text(str(roundi(value)))
