extends Control
class_name BattleOverlay

enum Outcome { WIN, LOSE, ESCAPE }

signal battle_finished(outcome: Outcome)

@export var starting_hp: int = 50
@export var starting_toll: int = 0
@export var enemy_head_height: float = 1.8
@export var rising_number_rise_px: float = 60.0
@export var rising_number_duration_sec: float = 0.6

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
# the Deck and the enemies list, the only thing hand_container/this overlay
# ever call into to report input or drive rules. Called by region_field.gd
# right alongside CameraRig's own enter_battle().
func enter_battle(on_dark_world: bool, enemies: Array[FieldEnemy]) -> void:
	if theme is BattleTheme:
		(theme as BattleTheme).apply_value_set(on_dark_world)

	battle_controller = BattleController.new()
	add_child(battle_controller)
	battle_controller.target_requested.connect(_on_target_requested)
	battle_controller.target_cancelled.connect(_on_target_cancelled)
	battle_controller.card_played.connect(_on_card_played)
	battle_controller.setup(hand_container, enemies)

	end_turn_button.pressed.connect(func() -> void: battle_controller.end_turn())

func _on_target_requested(_card: CardData) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_target_cancelled() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_card_played(card: CardData, target: FieldEnemy) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if target != null:
		_spawn_rising_number(card.cost, target)

# Placeholder-only: reads card.cost, not any real effect value - see this
# pass's own out-of-scope note (no real effects/HP/Toll yet).
func _spawn_rising_number(value: int, target: FieldEnemy) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen_pos: Vector2 = camera.unproject_position(target.global_position + Vector3.UP * enemy_head_height)

	var label := Label.new()
	label.text = str(value)
	label.position = screen_pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", screen_pos.y - rising_number_rise_px, rising_number_duration_sec)
	tween.tween_property(label, "modulate:a", 0.0, rising_number_duration_sec)
	tween.chain().tween_callback(label.queue_free)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		debug_row.visible = not debug_row.visible
		get_viewport().set_input_as_handled()
