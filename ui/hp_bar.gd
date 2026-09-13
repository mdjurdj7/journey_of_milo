extends PanelContainer
class_name HPBar

# The player's own HP readout - a thin bar with current/max beneath it,
# floating just under the Wanderer's feet in both field and battle (one
# persistent instance, living in FieldHUD - see region_field.gd's own
# set_target() call). Repositioned every frame via unproject, the same
# shape EnemyStatus already uses for enemies (see that script's own doc) -
# the anchor point is the Wanderer's own ground position plus ground_
# offset, not head height, so the offset points DOWN by default.
#
# Reads RunState.player_hp/player_max_hp directly and updates on RunState.
# player_hp_changed - the only source this bar ever reads, in field or
# battle alike. In battle, BattleOverlay.enter_battle() also calls show_
# toll()/update_toll() to show a Toll reading beside the bar (this panel
# has no live Toll source of its own - Toll is battle-scoped, not part of
# RunState) and hide_toll() when the battle ends.
#
# Field visibility (see HoverFadeVisibility): hidden by default, fades in
# on mouse hover over the Wanderer or on any HP change (held briefly, then
# faded back out), stays visible below low_hp_fraction, and is always
# fully visible in battle (see enter_battle()/exit_battle(), called by
# BattleOverlay alongside show_toll()/hide_toll()).

@export var ground_offset: Vector3 = Vector3(0.0, -0.2, 0.0)
@export var bar_tween_time: float = 0.25
@export var toll_label_prefix: String = "Toll: "
@export var fade_time: float = 0.15
@export var hp_change_hold_time: float = 1.5
@export_range(0.0, 1.0) var low_hp_fraction: float = 0.3

@onready var _numbers_label: Label = $Content/VBox/NumbersLabel
@onready var _bar_background: ColorRect = $Content/VBox/BarBackground
@onready var _bar_fill: ColorRect = $Content/VBox/BarBackground/BarFill
@onready var _toll_label: Label = $Content/TollLabel

var _wanderer: Wanderer = null
var _bar_width: float = 0.0
var _current_fraction: float = 1.0
var _bar_width_tween: Tween = null
var _in_battle: bool = false
var _visibility: HoverFadeVisibility = null

func _ready() -> void:
	# FieldHUD (this panel's parent) already sets PROCESS_MODE_ALWAYS, so
	# this is inherited already - set explicitly anyway so _process() below
	# is guaranteed to keep tracking the Wanderer through RegionField's own
	# battle-contact freeze (including the stance-tween-in step) regardless
	# of where this node ever ends up parented.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toll_label.visible = false
	_bar_width = _bar_background.custom_minimum_size.x
	_visibility = HoverFadeVisibility.new(self, fade_time, hp_change_hold_time)

	refresh_style()

	RunState.player_hp_changed.connect(_on_player_hp_changed)
	_current_fraction = _hp_fraction(RunState.player_hp, RunState.player_max_hp)
	_refresh_numbers(RunState.player_hp, RunState.player_max_hp)
	_bar_fill.size.x = _bar_width * _current_fraction

# Called once by region_field.gd - the Wanderer this bar tracks. Safe to
# call before or after _ready(); _process() below just no-ops until it's
# set.
func set_target(wanderer: Wanderer) -> void:
	_wanderer = wanderer

# Re-reads this panel's theme colors - called by RegionField right after
# it applies the region's on-pale/on-dark value set to the shared
# BattleTheme resource, same "cached once, refreshed on demand" shape
# EnemyStatus/DeckPanel/CardView already use rather than tracking the
# theme resource live. The panel's own background comes free from the
# shared BattleTheme's PanelContainer stylebox (see ui/battle_theme.gd) -
# nothing here needs to build one.
func refresh_style() -> void:
	_bar_background.color = get_theme_color("panel_light_color", "CardFace")
	_bar_fill.color = get_theme_color("text_color", "CardFace")

func _process(delta: float) -> void:
	if _wanderer == null or not is_instance_valid(_wanderer):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_pos: Vector2 = camera.unproject_position(_wanderer.global_position + ground_offset)
	position = screen_pos - size / 2.0

	var hovered: bool = not _in_battle and HoverRaycast.is_hovering(get_viewport(), _wanderer)
	var low_hp: bool = _current_fraction <= low_hp_fraction
	_visibility.update(delta, hovered, low_hp, _in_battle)

func _hp_fraction(current: int, max_hp: int) -> float:
	if max_hp <= 0:
		return 0.0
	return clampf(float(current) / float(max_hp), 0.0, 1.0)

func _on_player_hp_changed(current: int, max_hp: int) -> void:
	_refresh_numbers(current, max_hp)
	_current_fraction = _hp_fraction(current, max_hp)
	_tween_bar_to(_current_fraction)
	_visibility.notify_hp_changed()

func _refresh_numbers(current: int, max_hp: int) -> void:
	_numbers_label.text = "%d/%d" % [current, max_hp]

func _tween_bar_to(fraction: float) -> void:
	if _bar_width_tween != null:
		_bar_width_tween.kill()
	_bar_width_tween = create_tween()
	_bar_width_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bar_width_tween.tween_property(_bar_fill, "size:x", _bar_width * fraction, bar_tween_time)

# Called by BattleOverlay.enter_battle()/_finish_battle() alongside show_
# toll()/hide_toll() - bypasses the field hover/hold/low-hp visibility
# rules entirely while true (see HoverFadeVisibility.update()).
func enter_battle() -> void:
	_in_battle = true

func exit_battle() -> void:
	_in_battle = false

# Called by BattleOverlay.enter_battle() - shows a Toll reading beside the
# bar. initial_toll is shown immediately; BattleController.setup() emits
# the real value synchronously right after this call returns (see Battle
# Overlay.enter_battle()'s own connect-then-setup order), so there's no
# visible stale-number frame.
func show_toll(initial_toll: int) -> void:
	_toll_label.text = toll_label_prefix + str(initial_toll)
	_toll_label.visible = true

func update_toll(new_toll: int) -> void:
	if not _toll_label.visible:
		return
	_toll_label.text = toll_label_prefix + str(new_toll)

func hide_toll() -> void:
	_toll_label.visible = false
