extends RefCounted
class_name HoverFadeVisibility

# Shared field-visibility controller for a floating HP display (HPBar,
# EnemyStatus) - hidden by default, fades in over fade_time on hover or
# on any HP change (holding briefly - see notify_hp_changed() - before
# fading back out), stays visible while low_hp is true, and is always
# fully (and instantly) visible in battle. The owning script computes
# hovered/low_hp/in_battle itself each frame (this class stays ignorant of
# 3D raycasting, RunState, or Combatant HP - same "caller decides what
# triggered it" split EffectContext already uses for battle rules) and
# just calls update() every _process().

var _owner: CanvasItem
var _fade_time: float
var _hold_time: float

var _hold_timer: float = 0.0
var _fade_tween: Tween = null
var _visible_state: bool = false

func _init(owner: CanvasItem, fade_time: float, hold_time: float) -> void:
	_owner = owner
	_fade_time = fade_time
	_hold_time = hold_time
	_owner.modulate.a = 0.0

# Called whenever the owner's HP actually changed this frame - (re)starts
# the hold window, so hovering away right after a hit doesn't cut the
# reveal short.
func notify_hp_changed() -> void:
	_hold_timer = _hold_time

func update(delta: float, hovered: bool, low_hp: bool, in_battle: bool) -> void:
	if in_battle:
		_set_visible(true, 0.0)
		return

	if _hold_timer > 0.0:
		_hold_timer = maxf(_hold_timer - delta, 0.0)

	var should_show: bool = hovered or low_hp or _hold_timer > 0.0
	_set_visible(should_show, _fade_time)

func _set_visible(should_show: bool, duration: float) -> void:
	if should_show == _visible_state:
		return
	_visible_state = should_show
	if _fade_tween != null:
		_fade_tween.kill()
	if duration <= 0.0:
		_owner.modulate.a = 1.0 if should_show else 0.0
		return
	_fade_tween = _owner.create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_owner, "modulate:a", 1.0 if should_show else 0.0, duration)
