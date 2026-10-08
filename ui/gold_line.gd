extends InkLine
class_name GoldLine

# The field HUD row's gold: a stamped coin (InkGlyph's, the loot
# screen's mark too), the numeral, "GOLD" - after TOLL, before GLASSBONE
# and the keepsake, which hide themselves when empty, so GOLD never moves
# when they come or go (see InkLine for the shape, the style and the
# following). Always shown on the field, 0 included.
#
# A rise counts the numeral up to the new total over count_up_time,
# eased out, rather than jumping - it lands on the exact total. A fall
# (spending) snaps. The line's own tween, pause-proof, so it runs while
# the reward screen holds the field frozen (InkLine runs ALWAYS).
#
# RegionField creates it in _setup_field_hud() and hands it the TOLL
# line (sit_beside()); RunState.gold_changed keeps it current. It goes
# with the field row when BattleOverlay hides that for a fight.

# Seconds for the numeral to count up to a new total. A Remote-tab edit
# mid-count re-targets the running count over the new time.
@export var count_up_time: float = 0.6:
	set(value):
		count_up_time = value
		if _count_tween != null and _count_tween.is_valid():
			_start_count()

var _target: int = 0
var _shown: float = 0.0
var _count_tween: Tween = null

func _init() -> void:
	label_text = "GOLD"
	glyph = InkGlyph.Kind.GOLD
	_value_text = "0"

func _ready() -> void:
	super()
	RunState.gold_changed.connect(set_gold)
	snap_gold(RunState.gold)

# Counts the numeral up to `gold` from wherever it shows now; a fall
# below the current total snaps.
func set_gold(gold: int) -> void:
	var total: int = maxi(gold, 0)
	if total < _target:
		snap_gold(total)
		return
	_target = total
	_start_count()

# Shows `gold` at once, no count.
func snap_gold(gold: int) -> void:
	_kill_count()
	_target = maxi(gold, 0)
	_set_shown(float(_target))

# A fresh count from the numeral shown now to _target over count_up_time.
func _start_count() -> void:
	_kill_count()
	if count_up_time <= 0.0 or not is_inside_tree():
		_set_shown(float(_target))
		return
	_count_tween = create_tween()
	_count_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_count_tween.tween_method(_set_shown, _shown, float(_target), count_up_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Lands on the exact total, whatever the last step's rounding.
	_count_tween.tween_callback(_set_shown.bind(float(_target)))

func _kill_count() -> void:
	if _count_tween != null:
		_count_tween.kill()
		_count_tween = null

func _set_shown(value: float) -> void:
	_shown = value
	set_value_text(str(roundi(value)))
