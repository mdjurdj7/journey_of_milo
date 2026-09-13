extends PanelContainer
class_name EnemyStatus

# One per FieldEnemy, owned and created by FieldEnemy itself (see its own
# _ready()) and parented under RegionField.field_hud - persistent for the
# enemy's whole life, in field and battle alike, not just created/freed
# per fight the way this used to work. A small dark panel (same
# PanelContainer style as HPBar, since neither sets a theme_type_variation
# of its own) showing a thin bar with "HP current/max" beneath it,
# repositioned every frame under the enemy's feet via unproject - same
# shape HPBar uses for the player (see that script's own doc).
#
# In battle, BattleOverlay reuses this same instance (via FieldEnemy.
# enemy_status - see its own doc) rather than creating a fresh one, wires
# it to BattleController's own enemy_hp_changed signal, and calls enter_
# battle()/exit_battle() alongside the same calls it makes on HPBar.
#
# IntentSlot is deliberately empty - reserved room beside the HP block for
# a future intent icon, not built this pass.

# Points down from the enemy's own ground position, same idea as HPBar.
# ground_offset - retune per enemy live (Remote tab) once a taller/
# shorter creature needs a different offset.
@export var bar_offset: Vector3 = Vector3(0.0, -0.2, 0.0)
@export var fade_time: float = 0.15
@export var hp_change_hold_time: float = 1.5
@export_range(0.0, 1.0) var low_hp_fraction: float = 0.3

@onready var hp_label: Label = $Content/VBox/HPLabel
@onready var bar_background: ColorRect = $Content/VBox/BarBackground
@onready var bar_fill: ColorRect = $Content/VBox/BarBackground/BarFill

var target: FieldEnemy
var _bar_width: float = 0.0
var _current_hp: int = -1
var _max_hp: int = 1
var _in_battle: bool = false
var _visibility: HoverFadeVisibility = null

# update_hp()/refresh_style() below can both be called before this node's
# own _ready() has run (FieldEnemy._spawn_enemy_status() calls update_hp()
# right after creating this instance, and RegionField._setup_field_hud()
# can call refresh_style() the same way - add_child()'s own _ready() call
# isn't guaranteed to have already resolved bar_background/bar_fill/
# hp_label by that point). _is_ready is set explicitly as the very first
# line of _ready() below, rather than trusting Node.is_node_ready()'s own
# timing relative to that same call - not worth the risk of guessing wrong
# about whether the engine's own flag is already true DURING _ready()'s
# body vs. only after it returns.
var _is_ready: bool = false

# See update_hp()'s own doc on why this exists. -1 is "nothing pending" (a
# real max_hp of 0 or less never happens - see EnemyData.max_hp's own
# default).
var _pending_current: int = -1
var _pending_max: int = -1

func _ready() -> void:
	_is_ready = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bar_width = bar_background.custom_minimum_size.x
	_visibility = HoverFadeVisibility.new(self, fade_time, hp_change_hold_time)
	refresh_style()
	if _pending_max != -1:
		_apply_hp(_pending_current, _pending_max)

# Re-reads this panel's theme colors - called once here at _ready() and
# again by RegionField.add_enemy_status()'s own caller (_setup_field_hud())
# once the shared BattleTheme resource's value set is actually applied,
# since this node is very likely created (see FieldEnemy._spawn_enemy_
# status()) before that ever runs - same "cached once, refreshed on
# demand" shape HPBar/DeckPanel/CardView already use. A no-op if called
# before _ready() (bar_background/bar_fill still null) - safe to skip,
# since _ready() calls this itself once it actually runs.
func refresh_style() -> void:
	if not _is_ready:
		return
	bar_background.color = get_theme_color("panel_light_color", "CardFace")
	bar_fill.color = get_theme_color("text_color", "CardFace")

func set_target(field_enemy: FieldEnemy) -> void:
	target = field_enemy

# Safe to call before this node has entered the tree (see _pending_
# current/_pending_max's own doc) - defers to _ready() in that case rather
# than touching hp_label/bar_background/bar_fill while they're still null.
func update_hp(current: int, max_hp: int) -> void:
	if not _is_ready:
		_pending_current = current
		_pending_max = max_hp
		return
	_apply_hp(current, max_hp)

# _current_hp starts at the -1 sentinel ("never set") - the very first
# real call (FieldEnemy's own field-mode seed at spawn, or battle setup()'s
# own initial full-HP emit right after) never counts as a "change" worth
# revealing the bar for, only a real move away from whatever it was
# already showing does.
func _apply_hp(current: int, max_hp: int) -> void:
	var changed: bool = _current_hp != -1 and current != _current_hp
	_current_hp = current
	_max_hp = max_hp

	hp_label.text = "HP %d/%d" % [current, max_hp]
	var fraction: float = float(current) / float(max_hp) if max_hp > 0 else 0.0
	bar_fill.size.x = _bar_width * clampf(fraction, 0.0, 1.0)

	if changed:
		_visibility.notify_hp_changed()

# Called by BattleOverlay when this enemy's fight starts/ends (see its own
# _create_enemy_statuses()/_finish_battle()) - bypasses the field hover/
# hold/low-hp visibility rules entirely while true (see HoverFadeVisibility
# .update()), same shape HPBar.enter_battle()/exit_battle() uses.
func enter_battle() -> void:
	_in_battle = true

func exit_battle() -> void:
	_in_battle = false

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_pos: Vector2 = camera.unproject_position(target.global_position + bar_offset)
	position = screen_pos - size / 2.0

	var hovered: bool = not _in_battle and HoverRaycast.is_hovering(get_viewport(), target)
	var low_hp: bool = _max_hp > 0 and float(_current_hp) / float(_max_hp) <= low_hp_fraction
	_visibility.update(delta, hovered, low_hp, _in_battle)
