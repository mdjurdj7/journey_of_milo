extends Control
class_name BattleOverlay

const FLOATING_NUMBER_SCENE_PATH := "res://battle/floating_number.tscn"
const ENEMY_STATUS_SCENE_PATH := "res://battle/enemy_status.tscn"

enum Outcome { WIN, LOSE, ESCAPE }

signal battle_finished(outcome: Outcome)

@export var starting_hp: int = 50
@export var starting_toll: int = 0
@export var enemy_head_height: float = 1.8

@onready var stats_panel: PanelContainer = $StatsPanel
@onready var hp_label: Label = $StatsPanel/StatsBox/HPLabel
@onready var toll_label: Label = $StatsPanel/StatsBox/TollLabel
@onready var end_turn_button: Button = $EndTurnButton
@onready var hand_container: HandContainer = $HandContainer
@onready var debug_row: Control = $DebugRow
@onready var win_button: Button = $DebugRow/WinButton
@onready var lose_button: Button = $DebugRow/LoseButton
@onready var escape_button: Button = $DebugRow/EscapeButton
@onready var draw_button: Button = $DebugRow/DrawButton
@onready var discard_button: Button = $DebugRow/DiscardButton

var battle_controller: BattleController
var _enemy_statuses: Dictionary = {} # FieldEnemy -> EnemyStatus

func _ready() -> void:
	# RegionField freezes itself (and, by inheritance, this whole overlay -
	# it's added under BattleLayer, RegionField's own child) on battle
	# contact. Every interactive piece here (cards, buttons, the controller
	# added in enter_battle()) needs to keep working through that freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Covers the full screen - a click meant for a 3D enemy behind it must
	# fall through to BattleController's own _unhandled_input() raycast
	# instead of being swallowed here. Cards/buttons keep their own STOP.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if theme is BattleTheme:
		(theme as BattleTheme).apply_value_set(false)

	hp_label.text = "HP: %d" % starting_hp
	toll_label.text = "Toll: %d" % starting_toll

	debug_row.visible = false

	win_button.pressed.connect(func() -> void: battle_finished.emit(Outcome.WIN))
	lose_button.pressed.connect(func() -> void: battle_finished.emit(Outcome.LOSE))
	escape_button.pressed.connect(func() -> void: battle_finished.emit(Outcome.ESCAPE))
	draw_button.pressed.connect(func() -> void: hand_container.draw_cards(5))
	discard_button.pressed.connect(func() -> void: hand_container.discard_hand())

# Reads RegionField's ui_on_dark_world switch and applies the matching
# value set to this overlay's theme (see ui/battle_theme.gd's own
# apply_value_set()), then builds this fight's BattleController - owner of
# the Deck/Combatants and the only thing hand_container/this overlay ever
# call into to report input or drive rules. Called by region_field.gd
# right alongside CameraRig's own enter_battle().
func enter_battle(on_dark_world: bool, enemy_list: Array[FieldEnemy]) -> void:
	if theme is BattleTheme:
		(theme as BattleTheme).apply_value_set(on_dark_world)

	# Created before battle_controller.setup() runs, and enemy_hp_changed
	# connected before it too - setup()'s own initial emission (one per
	# enemy) is what gives each panel its starting HP text/bar, with no
	# separate hydration step needed here.
	_create_enemy_statuses(enemy_list)

	battle_controller = BattleController.new()
	add_child(battle_controller)
	battle_controller.target_requested.connect(_on_target_requested)
	battle_controller.target_cancelled.connect(_on_target_cancelled)
	battle_controller.card_played.connect(_on_card_played)
	battle_controller.hp_changed.connect(_on_hp_changed)
	battle_controller.toll_changed.connect(_on_toll_changed)
	battle_controller.enemy_hp_changed.connect(_on_enemy_hp_changed)
	battle_controller.damage_dealt.connect(_on_damage_dealt)
	battle_controller.battle_won.connect(func() -> void: battle_finished.emit(Outcome.WIN))
	battle_controller.battle_lost.connect(func() -> void: battle_finished.emit(Outcome.LOSE))
	battle_controller.setup(hand_container, enemy_list)

	end_turn_button.pressed.connect(func() -> void: battle_controller.end_turn())

# One EnemyStatus per enemy, as this overlay's own children - freed
# automatically when region_field.gd frees the whole overlay at battle
# end, same as every other child here (HandContainer, StatsPanel, ...).
func _create_enemy_statuses(enemy_list: Array[FieldEnemy]) -> void:
	for enemy in enemy_list:
		var status := (load(ENEMY_STATUS_SCENE_PATH) as PackedScene).instantiate() as EnemyStatus
		add_child(status)
		status.set_target(enemy)
		_enemy_statuses[enemy] = status

func _on_enemy_hp_changed(enemy: FieldEnemy, current: int, max_hp: int) -> void:
	var status: EnemyStatus = _enemy_statuses.get(enemy)
	if status != null:
		status.update_hp(current, max_hp)

func _on_target_requested(_card: CardData) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_target_cancelled() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_card_played(_card: CardData, _target: FieldEnemy) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_hp_changed(current: int, max_hp: int) -> void:
	hp_label.text = "HP: %d/%d" % [current, max_hp]

func _on_toll_changed(new_toll: int) -> void:
	toll_label.text = "Toll: %d" % new_toll

# Placeholder-only: shows whatever amount actually landed, no distinction
# between damage/self-damage/attack kinds yet - see this pass's own
# out-of-scope note (no real effect polish beyond the numbers themselves).
func _on_damage_dealt(_source: Variant, target: Variant, amount: int, _kind: String) -> void:
	_spawn_floating_number(amount, _screen_pos_for_damage_target(target))

func _screen_pos_for_damage_target(target: Variant) -> Vector2:
	if target is FieldEnemy:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			return camera.unproject_position((target as FieldEnemy).global_position + Vector3.UP * enemy_head_height)
	# "player" (or anything else without a 3D position this overlay can
	# reach) - anchor near the stats panel instead of unprojecting a
	# Wanderer position this overlay has no reference to.
	return stats_panel.global_position + Vector2(stats_panel.size.x / 2.0, stats_panel.size.y + 20.0)

func _spawn_floating_number(value: int, screen_pos: Vector2) -> void:
	var number := (load(FLOATING_NUMBER_SCENE_PATH) as PackedScene).instantiate() as FloatingNumber
	add_child(number)
	number.show_value(value, screen_pos)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		debug_row.visible = not debug_row.visible
		get_viewport().set_input_as_handled()
