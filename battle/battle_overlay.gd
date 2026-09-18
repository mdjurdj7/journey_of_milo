extends Control
class_name BattleOverlay

const FLOATING_NUMBER_SCENE_PATH := "res://battle/floating_number.tscn"
const CARD_PLAY_SFX_PATH := "res://assets/audio/cards/card_play.wav"

enum Outcome { WIN, LOSE, ESCAPE }

signal battle_finished(outcome: Outcome)

@export var enemy_head_height: float = 1.8
# Every card's own shared "played" cue (see _on_card_played()) - fires the
# instant a card commits to play, independent of that card's own
# impact_time delay (that's Wanderer's slash sound, not this). Not a
# per-card override; every card uses this same one today.
@export var card_play_volume_db: float = -6.0

@export_group("Corners")
# The fixed readouts' inset from the viewport's edges: bottom-left the
# BattleResources stack (energy, Toll) with the DECK line beneath it,
# bottom-right End Turn with the DISCARD line beneath it - see
# _layout_corners().
@export var corner_margin_px: float = 40.0
# Between a stack and the pile line under it.
@export var stack_gap_px: float = 10.0

@onready var end_turn_button: EndTurnButton = $EndTurnButton
@onready var hand_container: HandContainer = $HandContainer
@onready var debug_row: Control = $DebugRow
@onready var win_button: Button = $DebugRow/WinButton
@onready var lose_button: Button = $DebugRow/LoseButton
@onready var escape_button: Button = $DebugRow/EscapeButton
@onready var draw_button: Button = $DebugRow/DrawButton
@onready var discard_button: Button = $DebugRow/DiscardButton

var battle_controller: BattleController
var _enemy_statuses: Dictionary = {} # FieldEnemy -> EnemyStatus
# One BattleIntent per enemy for this fight - children of this overlay,
# so they're freed with it and nothing of them exists on the field.
var _enemy_intents: Dictionary = {} # FieldEnemy -> BattleIntent
var _intents_revealed: bool = false
var _field_hp_bar: HPBar = null
var _field_deck_panel: DeckPanel = null
var _battle_transition_time: float = 0.0
var _card_play_player: AudioStreamPlayer = null
var _resources: BattleResources = null
var _deck_readout: PileReadout = null
var _discard_readout: PileReadout = null
# The theme's current value set (see enter_battle()/_flip_dark_world()).
var _on_dark_world: bool = false
# End Turn is enabled only while both hold - see _update_end_turn().
var _player_turn: bool = true
var _card_armed: bool = false

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

	debug_row.visible = false
	for button: Button in [win_button, lose_button, escape_button, draw_button, discard_button]:
		button.theme_type_variation = &"DebugButton"

	win_button.pressed.connect(func() -> void: _finish_battle(Outcome.WIN))
	lose_button.pressed.connect(func() -> void: _finish_battle(Outcome.LOSE))
	escape_button.pressed.connect(func() -> void: _finish_battle(Outcome.ESCAPE))
	draw_button.pressed.connect(func() -> void: hand_container.draw_cards(5))
	discard_button.pressed.connect(func() -> void: hand_container.discard_hand())

	resized.connect(_layout_corners)

# Reads RegionField's ui_on_dark_world switch and applies the matching
# value set to this overlay's theme (see ui/battle_theme.gd's own
# apply_value_set()), then builds this fight's BattleController - owner of
# the Deck/Combatants and the only thing hand_container/this overlay ever
# call into to report input or drive rules. Called by region_field.gd
# right alongside CameraRig's own enter_battle(). field_deck_panel is the
# field HUD's own persistent DeckPanel (not this overlay's child - it
# outlives every battle) - hidden for the fight (the DECK line bottom-left
# takes its place) and shown again by _finish_battle(). field_hp_bar is
# that same HUD's persistent HPBar (also not this overlay's child, also
# outlives every battle) - it already reads RunState.player_hp/
# player_max_hp on its own, so this call only switches it to its battle
# style and feeds it block. battle_transition_time is CameraRig's own
# battle_transition_time (region_field.gd reads it off the same rig it
# hands to Wanderer.enter_battle_stance()) - passed through to HPBar/
# EnemyStatus's own enter_battle() so their field->battle style tween
# (see HPBar._battle_blend's own doc) takes exactly as long as the camera
# swing/stance step, rather than an unrelated separate duration. wanderer
# is the same Wanderer region_field.gd already has in scope - handed to
# BattleController (clip-length lookups for its own impact-delay timing)
# and BattleFeedback (the actor its own reactions apply to for an enemy
# attack) rather than either re-finding it on its own.
func enter_battle(on_dark_world: bool, enemy_list: Array[FieldEnemy], field_deck_panel: DeckPanel, field_hp_bar: HPBar, battle_transition_time: float, wanderer: Wanderer) -> void:
	_on_dark_world = on_dark_world
	if theme is BattleTheme:
		(theme as BattleTheme).apply_value_set(on_dark_world)

	_battle_transition_time = battle_transition_time

	_field_hp_bar = field_hp_bar
	_field_hp_bar.enter_battle(battle_transition_time)
	_field_deck_panel = field_deck_panel
	_field_deck_panel.visible = false

	# Reused before battle_controller.setup() runs, and enemy_hp_changed
	# connected before it too - setup()'s own initial emission (one per
	# enemy) is what gives each panel its starting HP text/bar, with no
	# separate hydration step needed here.
	_create_enemy_statuses(enemy_list, battle_transition_time)

	# Intent displays exist before setup() so its first enemy_intent_
	# changed (one per enemy) lands on them; they stay hidden until the
	# battle frame has settled (see the timer below), and hide again while
	# an enemy acts.
	_create_enemy_intents(enemy_list)

	# The fixed corner readouts exist before setup() too, for the same
	# reason - its energy/toll emissions are their first values.
	_create_corner_readouts()

	battle_controller = BattleController.new()
	add_child(battle_controller)
	battle_controller.target_requested.connect(_on_target_requested)
	battle_controller.target_cancelled.connect(_on_target_cancelled)
	battle_controller.card_played.connect(_on_card_played)
	battle_controller.toll_changed.connect(_on_toll_changed)
	battle_controller.enemy_hp_changed.connect(_on_enemy_hp_changed)
	battle_controller.damage_dealt.connect(_on_damage_dealt)
	battle_controller.enemy_intent_changed.connect(_on_enemy_intent_changed)
	battle_controller.energy_changed.connect(hand_container.update_playable)
	battle_controller.energy_changed.connect(_on_energy_changed)
	battle_controller.status_changed.connect(_on_status_changed)
	battle_controller.turn_phase_changed.connect(_on_turn_phase_changed)
	battle_controller.enemy_acting.connect(_on_enemy_acting)
	battle_controller.battle_won.connect(func() -> void: _finish_battle(Outcome.WIN))
	battle_controller.battle_lost.connect(func() -> void: _finish_battle(Outcome.LOSE))
	hand_container.armed_changed.connect(_on_card_armed_changed)
	battle_controller.setup(hand_container, enemy_list, wanderer)
	get_tree().create_timer(battle_transition_time).timeout.connect(_reveal_enemy_intents)

	var battle_feedback := BattleFeedback.new()
	add_child(battle_feedback)
	battle_feedback.setup(wanderer, on_dark_world)
	battle_controller.damage_dealt.connect(battle_feedback.on_damage_dealt)

	_deck_readout.bind_to_deck(battle_controller.deck, PileReadout.Pile.DRAW)
	_discard_readout.bind_to_deck(battle_controller.deck, PileReadout.Pile.DISCARD)
	_layout_corners()

	var target_line := TargetLine.new()
	add_child(target_line)
	target_line.setup(battle_controller)

	_card_play_player = AudioStreamPlayer.new()
	add_child(_card_play_player)
	_card_play_player.stream = load(CARD_PLAY_SFX_PATH) as AudioStream
	if _card_play_player.stream == null:
		push_warning("BattleOverlay: card-play SFX failed to load (%s); card-play audio disabled." % CARD_PLAY_SFX_PATH)

	end_turn_button.pressed.connect(func() -> void: battle_controller.end_turn())
	_update_end_turn()

	# Deferred until the stance step/style tween has actually settled ("at
	# rest" - measuring mid-transition would read a bar that hasn't
	# finished growing yet) - see _debug_print_enemy_bar_gaps()'s own doc.
	get_tree().create_timer(battle_transition_time).timeout.connect(_debug_print_enemy_bar_gaps)

# The bottom-left resource stack and the two pile lines - this overlay's
# own children, freed with it. Bound/placed once the controller's Deck
# exists (see enter_battle()).
func _create_corner_readouts() -> void:
	_resources = BattleResources.new()
	add_child(_resources)
	_deck_readout = PileReadout.new()
	add_child(_deck_readout)
	_discard_readout = PileReadout.new()
	_discard_readout.align_right = true
	add_child(_discard_readout)

# Bottom-left: DECK line flush in the corner, the resource stack
# stack_gap_px above it. Bottom-right: DISCARD line flush in the corner,
# End Turn's rule stack_gap_px above it. Each readout keeps its own
# corner edge when its text changes size (see their _relayout()s), so
# this only needs re-running on a viewport resize.
func _layout_corners() -> void:
	if _resources == null or _deck_readout == null or _discard_readout == null:
		return
	var right: float = size.x - corner_margin_px
	var bottom: float = size.y - corner_margin_px

	_deck_readout.position = Vector2(corner_margin_px, bottom - _deck_readout.size.y)
	var stack_bottom: float = _deck_readout.position.y - stack_gap_px
	_resources.position = Vector2(corner_margin_px, stack_bottom - _resources.size.y)

	_discard_readout.position = Vector2(right - _discard_readout.size.x, bottom - _discard_readout.size.y)
	var end_turn_rule_bottom: float = _discard_readout.position.y - stack_gap_px
	end_turn_button.position = Vector2(right - end_turn_button.size.x, end_turn_rule_bottom - end_turn_button.rule_bottom())

# Reuses each enemy's own persistent EnemyStatus (see FieldEnemy.
# enemy_status's own doc) rather than creating a fresh one - these live
# in RegionField.field_hud and outlive this overlay, so there's nothing to
# free at battle end beyond entering/exiting battle mode (see
# _finish_battle()).
func _create_enemy_statuses(enemy_list: Array[FieldEnemy], duration: float) -> void:
	for enemy in enemy_list:
		var status := enemy.enemy_status
		if status == null:
			continue
		status.enter_battle(duration)
		_enemy_statuses[enemy] = status

func _on_enemy_hp_changed(enemy: FieldEnemy, current: int, max_hp: int) -> void:
	var status: EnemyStatus = _enemy_statuses.get(enemy)
	if status != null:
		status.update_hp(current, max_hp)

func _create_enemy_intents(enemy_list: Array[FieldEnemy]) -> void:
	for enemy in enemy_list:
		var intent := BattleIntent.new()
		add_child(intent)
		intent.set_target(enemy)
		_enemy_intents[enemy] = intent

# Once the camera swing/stance step has settled - the same delay HPBar/
# EnemyStatus's style tween takes - every display with an intent shows.
func _reveal_enemy_intents() -> void:
	_intents_revealed = true
	for intent: BattleIntent in _enemy_intents.values():
		if is_instance_valid(intent):
			intent.set_revealed(true)

# After setup, after each card resolves, at each turn start, and right
# after an enemy has acted (its NEXT action) - see BattleController's own
# signal doc. A display hidden for the enemy's action is revealed again
# here, with the new intent.
func _on_enemy_intent_changed(enemy: FieldEnemy, preview: Dictionary) -> void:
	var intent: BattleIntent = _enemy_intents.get(enemy)
	if intent == null or not is_instance_valid(intent):
		return
	intent.show_intent(preview)
	if _intents_revealed:
		intent.set_revealed(true)

func _on_enemy_acting(enemy: FieldEnemy) -> void:
	var intent: BattleIntent = _enemy_intents.get(enemy)
	if intent != null and is_instance_valid(intent):
		intent.set_revealed(false)

func _on_energy_changed(current: int) -> void:
	_resources.set_energy(current, battle_controller.player.max_energy)

func _on_toll_changed(new_toll: int) -> void:
	_resources.set_toll(new_toll)

# Block moved somewhere (a card, a turn start, an enemy's own guard) -
# every readout's segment follows.
func _on_status_changed() -> void:
	_field_hp_bar.set_block(battle_controller.player.block)
	for enemy: FieldEnemy in _enemy_statuses:
		var status: EnemyStatus = _enemy_statuses[enemy]
		if status != null and is_instance_valid(status):
			status.set_block(battle_controller.get_enemy_block(enemy))

func _on_turn_phase_changed(player_turn: bool) -> void:
	_player_turn = player_turn
	_update_end_turn()

func _on_card_armed_changed(armed: bool) -> void:
	_card_armed = armed
	_update_end_turn()

func _update_end_turn() -> void:
	end_turn_button.set_enabled(_player_turn and not _card_armed)

func _on_target_requested(_card: CardData) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_target_cancelled() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_card_played(_card: CardData, _target: FieldEnemy) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if _card_play_player != null and _card_play_player.stream != null:
		_card_play_player.volume_db = card_play_volume_db
		_card_play_player.play()

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
	# reach) - anchor near the field HP bar instead of unprojecting a
	# Wanderer position this overlay has no reference to.
	return _field_hp_bar.global_position + Vector2(_field_hp_bar.size.x / 2.0, _field_hp_bar.size.y + 20.0)

# The one path every battle-ending trigger (WIN/LOSE/ESCAPE debug buttons,
# battle_controller.battle_won/battle_lost) now goes through, rather than
# emitting battle_finished directly - the field readouts have to leave
# battle style (and the field DeckPanel come back) before region_field.gd
# reacts to battle_finished and frees this overlay.
func _finish_battle(outcome: Outcome) -> void:
	_field_hp_bar.exit_battle(_battle_transition_time)
	if _field_deck_panel != null:
		_field_deck_panel.visible = true
	for status: EnemyStatus in _enemy_statuses.values():
		status.exit_battle(_battle_transition_time)
	battle_finished.emit(outcome)

# One-shot, per battle: how much clearance each enemy's under-feet HP
# readout actually has above HandContainer's own top edge, once the
# stance step/style tween has settled. CameraRig's battle fit puts the
# lowest feet hand_clearance (a viewport-height fraction) above that edge
# - this prints what the readout under them is left with, which can't be
# verified without running the game. Read it from the console after a
# real fight and retune hand_clearance if it sits too close.
func _debug_print_enemy_bar_gaps() -> void:
	for enemy: FieldEnemy in _enemy_statuses:
		var status: EnemyStatus = _enemy_statuses[enemy]
		if status == null or not is_instance_valid(status):
			continue
		var bar_bottom: Vector2 = status.get_global_transform() * Vector2(status.size.x / 2.0, status.size.y)
		# Against the resting cards' actual top edge, not the container's
		# (the cards sit well below it - see HandContainer.get_rest_top_y()).
		var gap: float = hand_container.get_rest_top_y() - bar_bottom.y
		print("BattleOverlay: enemy '%s' HP readout bottom-to-hand gap = %.1f px" % [enemy.enemy_id, gap])
	if _field_hp_bar != null:
		var hp_bottom: float = (_field_hp_bar.get_global_transform() * Vector2(0.0, _field_hp_bar.size.y)).y
		print("BattleOverlay: Wanderer HP readout bottom-to-hand gap = %.1f px" % (hand_container.get_rest_top_y() - hp_bottom))

func _spawn_floating_number(value: int, screen_pos: Vector2) -> void:
	var number := (load(FLOATING_NUMBER_SCENE_PATH) as PackedScene).instantiate() as FloatingNumber
	add_child(number)
	number.show_value(value, screen_pos)

# Debug: flips the theme between its on-pale and on-dark value sets and
# re-reads every battle readout's colours - the cards don't take part
# (CardView keeps its own tones), which is the point of checking.
func _flip_dark_world() -> void:
	_on_dark_world = not _on_dark_world
	if theme is BattleTheme:
		(theme as BattleTheme).apply_value_set(_on_dark_world)
	if _field_hp_bar != null:
		_field_hp_bar.refresh_style()
	if _field_deck_panel != null:
		_field_deck_panel.refresh_style()
	for status: EnemyStatus in _enemy_statuses.values():
		if is_instance_valid(status):
			status.refresh_style()
	for intent: BattleIntent in _enemy_intents.values():
		if is_instance_valid(intent):
			intent.refresh_style()
	if _resources != null:
		_resources.refresh_style()
	if _deck_readout != null:
		_deck_readout.refresh_style()
	if _discard_readout != null:
		_discard_readout.refresh_style()
	end_turn_button.refresh_style()
	print("BattleOverlay: ui_on_dark_world (debug flip) = %s" % str(_on_dark_world))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			debug_row.visible = not debug_row.visible
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			_flip_dark_world()
			get_viewport().set_input_as_handled()
