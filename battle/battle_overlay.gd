extends Control
class_name BattleOverlay

enum Outcome { WIN, LOSE, ESCAPE }

signal battle_finished(outcome: Outcome)

# Path -> copy count, same composition as the old project's STARTING_DECK
# (reference/old_project's run_state.gd) re-pointed at the trimmed
# CardData resources under cards/data/.
const STARTER_DECK_COUNTS: Dictionary = {
	"res://cards/data/slash.tres": 3,
	"res://cards/data/bite_down.tres": 2,
	"res://cards/data/brace.tres": 2,
	"res://cards/data/reckoning.tres": 1,
	"res://cards/data/down_payment.tres": 1,
}

@export var starting_hp: int = 50
@export var starting_toll: int = 0
@export var turn_draw_amount: int = 5

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

var deck: Deck

func _ready() -> void:
	# Safe default (on-pale) in case this scene is ever previewed or
	# instanced without enter_battle() being called - region_field.gd's
	# own call right after instancing is what actually decides this.
	if theme is BattleTheme:
		(theme as BattleTheme).apply_value_set(false)

	deck = Deck.new(_build_starting_deck())
	hand_container.set_deck(deck)

	hp_label.text = "HP: %d" % starting_hp
	toll_label.text = "Toll: %d" % starting_toll

	debug_row.visible = false

	win_button.pressed.connect(func() -> void: battle_finished.emit(Outcome.WIN))
	lose_button.pressed.connect(func() -> void: battle_finished.emit(Outcome.LOSE))
	escape_button.pressed.connect(func() -> void: battle_finished.emit(Outcome.ESCAPE))
	draw_button.pressed.connect(func() -> void: hand_container.draw_cards(turn_draw_amount))
	discard_button.pressed.connect(func() -> void: hand_container.discard_hand())

# Reads RegionField's ui_on_dark_world switch and applies the matching
# value set to this overlay's theme - see ui/battle_theme.gd's own
# apply_value_set(). Called by region_field.gd right alongside
# CameraRig's own enter_battle(), the same point in the flow.
func enter_battle(on_dark_world: bool) -> void:
	if theme is BattleTheme:
		(theme as BattleTheme).apply_value_set(on_dark_world)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		debug_row.visible = not debug_row.visible
		get_viewport().set_input_as_handled()

func _build_starting_deck() -> Array[CardData]:
	var cards: Array[CardData] = []
	for path: String in STARTER_DECK_COUNTS:
		var base_card: CardData = load(path) as CardData
		var copies: int = int(STARTER_DECK_COUNTS[path])
		for i in copies:
			cards.append(base_card.duplicate() as CardData)
	return cards
