extends Control
class_name BattleOverlay

const FLOATING_NUMBER_SCENE_PATH := "res://battle/floating_number.tscn"
const CARD_PLAY_SFX_PATH := "res://assets/audio/ui/card_played.mp3"
# An optional tick as a repeated hit's Toll is spent (BattleController.
# card_repeat_swing - Second Swing): the first of these that exists plays;
# none, and nothing does.
const TOLL_TICK_PATHS: Array[String] = [
	"res://assets/audio/cards/SecondSwing/toll_tick.wav",
	"res://assets/audio/cards/SecondSwing/toll_tick.mp3",
]
const CARD_DRAW_SFX_PATH := "res://assets/audio/ui/card_draw.wav"
# Draw-sound voices, oldest stolen: a turn's draw launches a card every
# 0.07 s and the take rings 0.4 s, so about six overlap. Each voice its
# own player, so one card's pitch jitter never bends another's.
const CARD_DRAW_VOICES := 6

enum Outcome { WIN, LOSE, ESCAPE }

signal battle_finished(outcome: Outcome)

@export var enemy_head_height: float = 1.8
# Every card's own shared "played" cue (see _on_card_played()) - fires the
# instant a card commits to play, independent of that card's own
# impact_time delay (the swing and the enemy's contact crack are the
# Wanderer's/FieldEnemy's, not this). Levels: a -6 dBFS take through
# this 2D player at -16 peaks about -22 dBFS - under the swing (~-20)
# and well under the contact (~-10.5).
@export var card_play_volume_db: float = -16.0
# A card with its own sound (CardData.play_sound_path - Self-Eater's
# swell today) plays that INSTEAD of the cue above, on a second SFX-bus
# player at this level: the same -16 by default, so the order swing <
# card play < contact holds, but its own export since the two files'
# loudness differ.
@export var card_override_volume_db: float = -16.0
# The toll tick's level (TOLL_TICK_PATHS), well under the card's own play
# sound - a quiet accent on the follow-up swing.
@export var toll_tick_volume_db: float = -24.0
# A repeated hit's damage number (BattleController.card_repeat_impact)
# sits this far from where its first hit's did, in screen pixels - up and
# to the side, so the two read as two blows.
@export var repeat_number_offset: Vector2 = Vector2(28.0, -34.0)
# The draw sound, once per card as it leaves the deck (HandContainer.
# draw_started): a -6 dBFS take at -22, 6 dB under card play, so a
# five-card draw is felt rather than loud. One take only (see DESIGN.md),
# so each play's pitch moves by up to +-this fraction instead of a
# round-robin. Both read at each play, so a Remote-tab edit applies from
# the next card.
@export var card_draw_volume_db: float = -22.0
@export_range(0.0, 0.5) var card_draw_pitch_jitter: float = 0.05

@export_group("Choice Prompt")
# An open hand choice says what it wants in one tracked-caps ink line,
# this far above the armed card, or above the hand for the end-of-turn
# keep (BattleController.hand_choice_*): its verb (SET ASIDE, CONSUME,
# KEEP), the count marked, the cap, and what to click to confirm (the
# armed card, or END TURN).
@export var choice_prompt_format: String = "%s %d / %d  ·  CLICK %s TO CONFIRM"
@export var choice_prompt_font_size_px: int = 13:
	set(value):
		choice_prompt_font_size_px = value
		_style_choice_prompt()
@export var choice_prompt_tracking_em: float = 0.16:
	set(value):
		choice_prompt_tracking_em = value
		_style_choice_prompt()
@export var choice_prompt_gap_px: float = 12.0
# The readout's line for Bide's set-aside cards while they wait, and the
# reveal under it that names them.
@export var set_aside_line_format: String = "Set aside %d"
@export var set_aside_reveal_format: String = "Back in your hand at the start of your next turn: %s."

@export_group("Corners")
# The fixed readouts' inset from the viewport's edges: bottom-left the
# DECK line, bottom-right End Turn with the DISCARD line beneath it - see
# _layout_corners(). The energy readout (BattleResources) is pinned at
# energy_anchor instead.
@export var corner_margin_px: float = 40.0
# Between End Turn's rule and the DISCARD line under it.
@export var stack_gap_px: float = 10.0
# The energy readout's place, overlay-local and fixed whatever the hand
# holds: its right edge (x) and its numeral's top (y) - it grows leftward
# from that edge. x is where a five-card hand used to put it; y raises it
# clear of the hand - its pips' bottom (y + 63 at 72 px with 18 x 5 pips)
# 12 px above a hovered card's top at five cards (762.4 at 1080p).
@export var energy_anchor: Vector2 = Vector2(419.5, 687.4):
	set(value):
		energy_anchor = value
		_apply_energy_anchor()
# Between the DECK line and the keepsake row under it - the row sits in
# the corner margin, so nothing above it moves.
@export var keepsake_row_gap_px: float = 4.0:
	set(value):
		keepsake_row_gap_px = value
		_layout_corners()

@export_group("Debug")
# The folders the F1 row's card picker lists - every CardData .tres in
# each, sorted by card name. Listed through ResourceLoader.list_directory(),
# which reports an exported build's .tres.remap entries under their
# original names.
@export var debug_card_dirs: PackedStringArray = PackedStringArray([
	"res://cards/data/",
	"res://cards/neutral/",
]):
	set(value):
		debug_card_dirs = value
		if _debug_card_picker != null:
			_debug_card_picker.clear()
			if debug_row.visible:
				_fill_debug_card_picker()

@onready var end_turn_button: EndTurnButton = $EndTurnButton
@onready var hand_container: HandContainer = $HandContainer
@onready var debug_row: Control = $DebugRow
@onready var win_button: Button = $DebugRow/WinButton
@onready var lose_button: Button = $DebugRow/LoseButton
@onready var escape_button: Button = $DebugRow/EscapeButton
@onready var draw_button: Button = $DebugRow/DrawButton
@onready var discard_button: Button = $DebugRow/DiscardButton

var battle_controller: BattleController
# The fight was ended from the debug row, not by its own rules - see
# _finish_debug().
var finished_by_debug: bool = false
# The debug row's card picker, filled from debug_card_dirs the first time
# the row shows.
var _debug_card_picker: OptionButton = null
# The fight's hit reactions - kept to read a play effect's pacing for the
# damage numbers (BattleFeedback.reaction_delay()).
var _battle_feedback: BattleFeedback = null
# A Toll blow's Toll as it landed, for its toll_changed; -1 = none.
var _toll_blow_from: int = -1
var _enemy_statuses: Dictionary = {} # FieldEnemy -> EnemyStatus
# One BattleIntent per enemy for this fight - children of this overlay,
# so they're freed with it and nothing of them exists on the field.
var _enemy_intents: Dictionary = {} # FieldEnemy -> BattleIntent
var _intents_revealed: bool = false
# The enemy turn is under way (turn_phase_changed(false) until (true)): a
# display hidden for its enemy's action takes the next intent but stays
# hidden until every enemy has acted and any redraw has run
# (BattleController._apply_intent_exclusions()) - then all show at once,
# as the player's turn begins. So a move the player sees never switches.
var _enemy_phase: bool = false
var _field_hp_bar: HPBar = null
var _field_deck_panel: DeckPanel = null
var _battle_transition_time: float = 0.0
var _card_play_player: AudioStreamPlayer = null
# The toll tick's player, made on first use (_on_card_repeat_swing()).
var _toll_tick_player: AudioStreamPlayer = null
# True through a repeat's impact frame: its damage numbers take
# repeat_number_offset. Released at that frame's end.
var _repeat_impact: bool = false
# The card whose cost the energy pips preview (HandContainer.cost_focus_
# changed), and whether a play is holding the preview until its spend
# lands - see _on_cost_focus_changed().
var _cost_focus: CardData = null
var _cost_preview_held: bool = false
var _card_draw_players: Array[AudioStreamPlayer] = []
var _card_draw_next: int = 0
# The per-card override's player, made on first use - see _on_card_played().
var _card_override_player: AudioStreamPlayer = null
var _resources: BattleResources = null
var _deck_readout: DeckPanel = null
var _discard_readout: DeckPanel = null
var _keepsake_row: KeepsakeRow = null
# The theme's current value set (see enter_battle()/_flip_dark_world()).
var _on_dark_world: bool = false
# End Turn is enabled only while both hold - see _update_end_turn().
var _player_turn: bool = true
var _card_armed: bool = false
# Bide's choice prompt (choice_prompt_*), and the name of the card whose
# choice is open - null/empty while none is.
var _choice_prompt: Label = null
var _choice_card_name: String = ""
var _choice_verb: String = ""

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

	win_button.pressed.connect(func() -> void: _finish_debug(Outcome.WIN))
	lose_button.pressed.connect(func() -> void: _finish_debug(Outcome.LOSE))
	escape_button.pressed.connect(func() -> void: _finish_debug(Outcome.ESCAPE))
	draw_button.pressed.connect(func() -> void: hand_container.draw_cards(5))
	discard_button.pressed.connect(func() -> void:
		RunLogger.event("debug_discard_hand", {})
		hand_container.discard_hand())
	_debug_card_picker = OptionButton.new()
	_debug_card_picker.name = "CardPicker"
	_debug_card_picker.theme_type_variation = &"DebugButton"
	debug_row.add_child(_debug_card_picker)
	var add_card_button := Button.new()
	add_card_button.name = "AddCardButton"
	add_card_button.theme_type_variation = &"DebugButton"
	add_card_button.text = "Add card"
	add_card_button.pressed.connect(_on_debug_add_card_pressed)
	debug_row.add_child(add_card_button)
	if OS.is_debug_build():
		var energy_button := Button.new()
		energy_button.name = "AddEnergyButton"
		energy_button.theme_type_variation = &"DebugButton"
		energy_button.text = "+1 Energy"
		energy_button.pressed.connect(_on_debug_add_energy_pressed)
		debug_row.add_child(energy_button)

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
# style, puts its Toll block on and feeds it block. battle_transition_
# time is CameraRig's own (region_field.gd reads it off the same rig it
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
	# Toll is the floor's, not the fight's: it opens on what was carried in.
	_field_hp_bar.show_toll(RunState.toll)
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
	# reason - its energy emission is their first value.
	_create_corner_readouts()
	# Drawn cards fly in from the DECK line.
	hand_container.set_draw_origin(_deck_readout)

	battle_controller = BattleController.new()
	add_child(battle_controller)
	battle_controller.target_requested.connect(_on_target_requested)
	battle_controller.target_cancelled.connect(_on_target_cancelled)
	battle_controller.card_played.connect(_on_card_played)
	battle_controller.toll_changed.connect(_on_toll_changed)
	battle_controller.grace_changed.connect(_on_grace_changed)
	battle_controller.stance_changed.connect(_on_stance_changed)
	battle_controller.enemy_hp_changed.connect(_on_enemy_hp_changed)
	battle_controller.damage_dealt.connect(_on_damage_dealt)
	battle_controller.enemy_intent_changed.connect(_on_enemy_intent_changed)
	battle_controller.energy_changed.connect(hand_container.update_playable)
	battle_controller.energy_changed.connect(_on_energy_changed)
	hand_container.cost_focus_changed.connect(_on_cost_focus_changed)
	# A play holds the outlined pips until its energy_changed turns them
	# spent.
	battle_controller.card_played.connect(func(_card: CardData, _target: FieldEnemy) -> void: _cost_preview_held = true)
	battle_controller.status_changed.connect(_on_status_changed)
	battle_controller.turn_phase_changed.connect(_on_turn_phase_changed)
	battle_controller.enemy_acting.connect(_on_enemy_acting)
	battle_controller.enemy_defeated.connect(_on_enemy_defeated)
	battle_controller.battle_won.connect(func() -> void: _finish_battle(Outcome.WIN))
	battle_controller.battle_lost.connect(func() -> void: _finish_battle(Outcome.LOSE))
	hand_container.armed_changed.connect(_on_card_armed_changed)
	battle_controller.hand_choice_started.connect(_on_hand_choice_started)
	battle_controller.hand_choice_changed.connect(_on_hand_choice_changed)
	battle_controller.hand_choice_ended.connect(_on_hand_choice_ended)
	# The hand's conditionals re-read on exactly the signals that can move
	# one - never per frame. card_played fires after the play is counted,
	# turn_phase_changed(true) after the count resets and last turn's
	# damage is settled.
	battle_controller.card_played.connect(func(_card: CardData, _target: FieldEnemy) -> void: _push_bonus_context())
	battle_controller.turn_phase_changed.connect(func(_player_turn: bool) -> void: _push_bonus_context())
	battle_controller.grace_changed.connect(func(_grace: int) -> void: _push_bonus_context())
	battle_controller.hp_changed.connect(func(_current: int, _max_hp: int) -> void: _push_bonus_context())
	battle_controller.toll_changed.connect(func(_toll: int) -> void: _push_bonus_context())
	# A status taken (Keen, a keepsake's) moves every Attack's printed damage.
	battle_controller.status_changed.connect(func() -> void: _push_bonus_context())
	# The armed card's damage reads against the enemy under the cursor.
	battle_controller.hovered_enemy_changed.connect(_on_hovered_enemy_changed)
	battle_controller.setup(hand_container, enemy_list, wanderer)
	_push_bonus_context()
	get_tree().create_timer(battle_transition_time).timeout.connect(_reveal_enemy_intents)

	_battle_feedback = BattleFeedback.new()
	add_child(_battle_feedback)
	_battle_feedback.setup(wanderer, on_dark_world)
	battle_controller.damage_dealt.connect(_battle_feedback.on_damage_dealt)
	battle_controller.enemy_hit_blocked.connect(_battle_feedback.on_enemy_hit_blocked)
	# A card's play effect (Blood Arc's stroke) goes down before its hits
	# report, over the enemies it can hit - and under their intent
	# readouts, the lowest of whose bottom edges it is handed. And the
	# heavy tier learns which card's hits these are (a Toll blow's floor).
	battle_controller.card_impact.connect(func(card: CardData) -> void:
		_battle_feedback.set_impact_card(card)
		# Its Toll before it's spent - the play's toll_changed follows.
		_toll_blow_from = battle_controller.player.toll if BattleFeedback.is_toll_blow(card) else -1
		_battle_feedback.on_card_impact(card, battle_controller.enemies, _lowest_intent_height()))
	battle_controller.card_repeat_swing.connect(_on_card_repeat_swing)
	battle_controller.card_repeat_impact.connect(func(_card: CardData) -> void:
		_repeat_impact = true
		set_deferred("_repeat_impact", false))

	_deck_readout.bind_to_deck(battle_controller.deck, DeckPanel.Pile.DRAW)
	_discard_readout.bind_to_deck(battle_controller.deck, DeckPanel.Pile.DISCARD)
	_refresh_keepsake_row()
	RunState.keepsake_changed.connect(func(_keepsake: TrinketData) -> void: _refresh_keepsake_row())
	_layout_corners()

	var target_line := TargetLine.new()
	add_child(target_line)
	target_line.setup(battle_controller)

	_card_play_player = AudioStreamPlayer.new()
	_card_play_player.bus = &"SFX"
	add_child(_card_play_player)
	_card_play_player.stream = load(CARD_PLAY_SFX_PATH) as AudioStream
	if _card_play_player.stream == null:
		push_warning("BattleOverlay: card-play SFX failed to load (%s); card-play audio disabled." % CARD_PLAY_SFX_PATH)

	var draw_stream := load(CARD_DRAW_SFX_PATH) as AudioStream
	if draw_stream == null:
		push_warning("BattleOverlay: card-draw SFX failed to load (%s); card-draw audio disabled." % CARD_DRAW_SFX_PATH)
	else:
		for i in CARD_DRAW_VOICES:
			var player := AudioStreamPlayer.new()
			player.bus = &"SFX"
			player.stream = draw_stream
			add_child(player)
			_card_draw_players.append(player)
	hand_container.draw_started.connect(_on_card_draw_started)

	end_turn_button.pressed.connect(func() -> void: battle_controller.end_turn())
	_update_end_turn()

	# Deferred until the stance step/style tween has actually settled ("at
	# rest" - measuring mid-transition would read a bar that hasn't
	# finished growing yet) - see _debug_print_enemy_bar_gaps()'s own doc.
	get_tree().create_timer(battle_transition_time).timeout.connect(_debug_print_enemy_bar_gaps)
	# What the HP readout's hover reveal keeps clear of - the hand at rest.
	get_tree().create_timer(battle_transition_time).timeout.connect(func() -> void: _field_hp_bar.set_hand_top_y(hand_container.get_rest_top_y()))

# The bottom-left resource stack and the two pile lines - this overlay's
# own children, freed with it. Bound/placed once the controller's Deck
# exists (see enter_battle()).
func _create_corner_readouts() -> void:
	_resources = BattleResources.new()
	add_child(_resources)
	# Its size changes with the numeral and the tally; the right edge and
	# the numeral's top hold.
	_resources.resized.connect(_apply_energy_anchor)
	_deck_readout = DeckPanel.new()
	add_child(_deck_readout)
	_discard_readout = DeckPanel.new()
	_discard_readout.align_right = true
	add_child(_discard_readout)
	_keepsake_row = KeepsakeRow.new()
	add_child(_keepsake_row)

# The keepsakes with no in-combat counter go in the row under DECK; one
# whose status counts is a counter line under the HP bar instead (see
# _refresh_standing_row()). One slot today (RunState.keepsake).
func _refresh_keepsake_row() -> void:
	var quiet: Array[TrinketData] = []
	var keepsake: TrinketData = RunState.keepsake
	if keepsake != null:
		var status: StatusData = keepsake.combat_start_status
		if status == null or status.self_loss_trigger_count <= 0:
			quiet.append(keepsake)
	_keepsake_row.set_keepsakes(quiet)

# Bottom-left: DECK line flush in the corner and the keepsake row
# keepsake_row_gap_px under it, in the corner margin; the energy readout
# at energy_anchor. Bottom-right: DISCARD line flush in the corner, End
# Turn's rule stack_gap_px above it. Each readout keeps its
# own corner edge when its text changes size (see their _relayout()s), so
# this only needs re-running on a viewport resize.
func _layout_corners() -> void:
	if _resources == null or _deck_readout == null or _discard_readout == null:
		return
	var right: float = size.x - corner_margin_px
	var bottom: float = size.y - corner_margin_px

	_deck_readout.position = Vector2(corner_margin_px, bottom - _deck_readout.size.y)
	if _keepsake_row != null:
		_keepsake_row.position = Vector2(corner_margin_px, bottom + keepsake_row_gap_px)
	_apply_energy_anchor()

	_discard_readout.position = Vector2(right - _discard_readout.size.x, bottom - _discard_readout.size.y)
	var end_turn_rule_bottom: float = _discard_readout.position.y - stack_gap_px
	end_turn_button.position = Vector2(right - end_turn_button.size.x, end_turn_rule_bottom - end_turn_button.rule_bottom())

# Right edge held at energy_anchor's x, left edge clamped to the corner
# margin - a very wide readout gives up its edge, not screen; the
# numeral's top on the anchor's y, whatever the readout's size. The
# keepsake row's hover text keeps to the readout's top row, so it never
# lands on the readout.
func _apply_energy_anchor() -> void:
	if _resources == null:
		return
	_resources.position = Vector2(maxf(energy_anchor.x - _resources.size.x, corner_margin_px), energy_anchor.y - _resources.numeral_ink_top())
	if _keepsake_row != null:
		_keepsake_row.set_reveal_floor_y(_resources.global_position.y)

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
# signal doc. A display hidden for the enemy's action takes its new
# intent here, and shows again once the enemy turn is over (_enemy_phase).
func _on_enemy_intent_changed(enemy: FieldEnemy, preview: Dictionary) -> void:
	var intent: BattleIntent = _enemy_intents.get(enemy)
	if intent == null or not is_instance_valid(intent):
		return
	intent.show_intent(preview)
	if _intents_revealed and not _enemy_phase:
		intent.set_revealed(true)

func _on_enemy_acting(enemy: FieldEnemy) -> void:
	var intent: BattleIntent = _enemy_intents.get(enemy)
	if intent != null and is_instance_valid(intent):
		intent.set_revealed(false)

# The member is out of the fight: its intent goes now, and its status
# leaves this overlay's hands - whoever takes the body off the field
# (FieldEnemy.settle_and_free(), or RegionField's win) frees the status
# with it, so nothing here may touch it again at _finish_battle().
func _on_enemy_defeated(enemy: FieldEnemy) -> void:
	var intent: BattleIntent = _enemy_intents.get(enemy)
	if intent != null and is_instance_valid(intent):
		intent.queue_free()
	_enemy_intents.erase(enemy)
	_enemy_statuses.erase(enemy)

func _on_energy_changed(current: int) -> void:
	_resources.set_energy(current, battle_controller.player.max_energy)
	_cost_preview_held = false
	_refresh_cost_preview()

func _on_cost_focus_changed(card: CardData) -> void:
	_cost_focus = card
	_refresh_cost_preview()

# The focused card's cost as outlined pips - the fight's own reading of
# it (Combatant.energy_cost(): a free card or a cost paid in HP is 0), and
# only when it can be paid; an unaffordable card is already dimmed. A
# play holds what it showed until its energy_changed.
func _refresh_cost_preview() -> void:
	if _resources == null or battle_controller == null or battle_controller.player == null:
		return
	if _cost_preview_held:
		return
	var cost: int = 0
	if _cost_focus != null:
		cost = battle_controller.player.energy_cost(_cost_focus)
		if cost > battle_controller.player.energy:
			cost = 0
	_resources.set_cost_preview(cost)

func _on_toll_changed(new_toll: int) -> void:
	# A Toll blow's spend pours into its hit: counted down, not snapped.
	var drained_from: int = _toll_blow_from
	_toll_blow_from = -1
	if drained_from > new_toll:
		_field_hp_bar.drain_toll(drained_from, new_toll)
	else:
		_field_hp_bar.update_toll(new_toll)
	# Reckoning and Debt Forgiven print numbers made of Toll.
	hand_container.set_toll(new_toll)

func _on_grace_changed(grace: int) -> void:
	_field_hp_bar.update_grace(grace)
	# A card whose number moves with Grace (CardEffect.Condition.HAS_GRACE)
	# prints its replacement while any is open.
	hand_container.set_grace(grace)

func _on_stance_changed(stance: Stance) -> void:
	_refresh_standing_row()
	# The hand's faces move with it - see HandContainer.set_stance().
	hand_container.set_stance(stance)

# Turns the player's rules state into the lines the row draws - this is
# the only place that knows a Stance/Status has a display_name or a stack
# count, so HPBar can stay a thing that draws what it is handed (see
# HPBar.set_standing_row()). One line each, top to bottom: the stance
# ("Self-Eater ×2" once stacked); every status in the order it was
# applied, as Status.label() reads it; the guards already spent this
# fight and not armed again, grey; then the counters ("The Return 2/5"), with
# their progress. Names as authored, in title case.
func _refresh_standing_row() -> void:
	var player: Combatant = battle_controller.player
	var lines: Array[Dictionary] = []
	var stance: Stance = player.stance
	if stance != null and stance.data != null:
		var stance_text: String = stance.data.display_name
		if stance.stacks > 1:
			stance_text += " ×%d" % stance.stacks
		lines.append({"text": stance_text, "glyph": true, "name": stance.data.display_name, "rules": stance.describe()})
	var counters: Array[Dictionary] = []
	for active: Status in player.statuses:
		if active.data == null:
			continue
		var line: Dictionary = {"text": active.label(), "name": active.data.display_name, "rules": active.describe(player)}
		if active.has_self_loss_counter():
			line["count"] = active.data.self_loss_trigger_count
			line["progress"] = active.progress
			counters.append(line)
		else:
			lines.append(line)
	# A spent status reads as spent - unless a copy played since has armed
	# it again (Refuse the End), when the live line says it all.
	for spent: StatusData in player.spent_statuses:
		if Status.find_in(player.statuses, spent) != null:
			continue
		lines.append({"text": spent.display_name, "spent": true, "name": spent.display_name, "rules": Status.new(spent).describe(player)})
	lines.append_array(counters)
	# Bide's cards, waiting for next turn - named in the reveal, so they
	# don't read as gone.
	var waiting: Array[CardData] = battle_controller.deck.set_aside_pile if battle_controller.deck != null else []
	if not waiting.is_empty():
		var names: PackedStringArray = []
		for card in waiting:
			names.append(card.card_name)
		lines.append({"text": set_aside_line_format % waiting.size(), "name": "Set aside", "rules": set_aside_reveal_format % ", ".join(names)})
	_field_hp_bar.set_standing_row(lines)
	_field_hp_bar.set_hand_top_y(hand_container.get_rest_top_y())

# Block moved somewhere (a card, a turn start, an enemy's own guard) -
# every readout's segment follows.
func _on_status_changed() -> void:
	_field_hp_bar.set_block(battle_controller.player.block)
	_refresh_standing_row()
	for enemy: FieldEnemy in _enemy_statuses:
		var status: EnemyStatus = _enemy_statuses[enemy]
		if status != null and is_instance_valid(status):
			status.set_block(battle_controller.get_enemy_block(enemy))
			status.set_status_row(battle_controller.get_enemy_status_labels(enemy))
			var reveal_names := PackedStringArray()
			var reveal_lines := PackedStringArray()
			for active: Status in battle_controller.get_enemy_statuses(enemy):
				if active.data == null or active.data.description.is_empty():
					continue
				reveal_names.append(active.data.display_name)
				reveal_lines.append(active.describe())
			status.set_reveal_lines(reveal_names, reveal_lines)

func _on_turn_phase_changed(player_turn: bool) -> void:
	_player_turn = player_turn
	_update_end_turn()
	_enemy_phase = not player_turn
	# Every enemy has acted and redrawn: their next moves show together.
	if player_turn and _intents_revealed:
		for intent: BattleIntent in _enemy_intents.values():
			if is_instance_valid(intent):
				intent.set_revealed(true)

# The hand's reading of the battle - see HandContainer.set_bonus_
# context() and the connections in enter_battle().
func _push_bonus_context() -> void:
	if battle_controller == null:
		return
	hand_container.set_bonus_context(battle_controller.preview_context())

# The hand back to the battle as it stands, then - while a card is armed
# and the cursor is over an enemy - that card's face aimed at it. Over no
# enemy, or once the card is played or cancelled, every face reads the
# base context again.
func _on_hovered_enemy_changed(enemy: FieldEnemy) -> void:
	_push_bonus_context()
	var armed: CardView = battle_controller.get_pending_card_view()
	if armed != null and enemy != null:
		hand_container.set_card_bonus_context(armed, battle_controller.preview_context_against(enemy))

func _on_card_armed_changed(armed: bool) -> void:
	_card_armed = armed
	_update_end_turn()

func _update_end_turn() -> void:
	end_turn_button.set_enabled(_player_turn and not _card_armed)

func _on_hand_choice_started(confirm_label: String, _cap: int, verb: String) -> void:
	_choice_card_name = confirm_label
	_choice_verb = verb
	if _choice_prompt == null:
		_choice_prompt = Label.new()
		_choice_prompt.name = "ChoicePrompt"
		_choice_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_choice_prompt)
	_style_choice_prompt()
	_choice_prompt.visible = true

func _on_hand_choice_changed(marked: int, cap: int) -> void:
	if _choice_prompt == null:
		return
	_choice_prompt.text = choice_prompt_format % [_choice_verb, marked, cap, _choice_card_name.to_upper()]
	_choice_prompt.size = Vector2.ZERO
	_place_choice_prompt()

func _on_hand_choice_ended() -> void:
	_choice_card_name = ""
	if _choice_prompt != null:
		_choice_prompt.visible = false

func _style_choice_prompt() -> void:
	if _choice_prompt == null:
		return
	_choice_prompt.add_theme_font_override("font", InkType.tracked(InkType.text_bold_font(), choice_prompt_font_size_px, choice_prompt_tracking_em))
	_choice_prompt.add_theme_font_size_override("font_size", choice_prompt_font_size_px)
	_choice_prompt.add_theme_color_override("font_color", get_theme_color("ink", "Battle"))

# Centred over the armed card's top edge, followed every frame while the
# card travels to its armed pose. With no card armed (the end-of-turn
# keep), centred over the hand's resting top edge instead.
func _place_choice_prompt() -> void:
	if _choice_prompt == null or not _choice_prompt.visible or battle_controller == null:
		return
	var card: CardView = battle_controller.get_choosing_card_view()
	var centre_x: float = hand_container.get_global_rect().get_center().x
	var top_y: float = hand_container.get_rest_top_y()
	if card != null:
		var rect: Rect2 = card.get_global_rect()
		centre_x = rect.get_center().x
		top_y = rect.position.y
	_choice_prompt.global_position = Vector2(centre_x - _choice_prompt.size.x / 2.0, top_y - choice_prompt_gap_px - _choice_prompt.size.y)

func _process(_delta: float) -> void:
	_place_choice_prompt()

func _on_target_requested(_card: CardData) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _on_target_cancelled() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# The card's own sound if it names one (CardData.play_sound_path), else
# the shared cue - one or the other, never both. Both fire here, at
# commit, and nowhere else: the override is not tied to anything the
# card does afterwards.
func _on_card_played(card: CardData, _target: FieldEnemy) -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if card != null and not card.play_sound_path.is_empty():
		var stream := load(card.play_sound_path) as AudioStream
		if stream != null:
			if _card_override_player == null:
				_card_override_player = AudioStreamPlayer.new()
				_card_override_player.bus = &"SFX"
				add_child(_card_override_player)
			_card_override_player.stream = stream
			_card_override_player.volume_db = card_override_volume_db
			_card_override_player.play()
			return
		push_warning("BattleOverlay: '%s' names a play sound that failed to load (%s); using the shared cue." % [card.card_name, card.play_sound_path])
	if _card_play_player != null and _card_play_player.stream != null:
		_card_play_player.volume_db = card_play_volume_db
		_card_play_player.play()

# A drawn card leaves the deck: the draw sound, on the next voice, its
# pitch jittered.
func _on_card_draw_started(_card: CardData) -> void:
	if _card_draw_players.is_empty():
		return
	var player: AudioStreamPlayer = _card_draw_players[_card_draw_next]
	_card_draw_next = (_card_draw_next + 1) % _card_draw_players.size()
	player.volume_db = card_draw_volume_db
	player.pitch_scale = 1.0 + randf_range(-card_draw_pitch_jitter, card_draw_pitch_jitter)
	player.play()

# Placeholder-only: shows whatever amount actually landed, no distinction
# between damage/self-damage/attack kinds yet - see this pass's own
# out-of-scope note (no real effect polish beyond the numbers themselves).
# The world height of the lowest enemy intent readout's bottom edge (INF
# with none) - the ceiling a play effect stays under.
func _lowest_intent_height() -> float:
	var lowest: float = INF
	for intent: BattleIntent in _enemy_intents.values():
		if intent != null and is_instance_valid(intent):
			lowest = minf(lowest, intent.anchor_height())
	return lowest

# The number waits with its enemy's hit reaction when a play effect paces
# them (BattleFeedback.reaction_delay()) - on scaled time, like the
# reaction - and is placed when it shows.
func _on_damage_dealt(_source: Variant, target: Variant, amount: int, _kind: String) -> void:
	var delay: float = _battle_feedback.reaction_delay(target) if _battle_feedback != null else 0.0
	# Read in the hit's own frame, while its card is still the impact's.
	var size: float = _battle_feedback.number_scale(target, amount) if _battle_feedback != null else 1.0
	var offset: Vector2 = repeat_number_offset if _repeat_impact and target is FieldEnemy else Vector2.ZERO
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if target is Object and not is_instance_valid(target):
			return
	_spawn_floating_number(amount, _screen_pos_for_damage_target(target) + offset, size)

# A repeated hit's follow-up swing (Second Swing): the toll tick, if one
# is on disk.
func _on_card_repeat_swing(_card: CardData, _target: FieldEnemy) -> void:
	var stream: AudioStream = null
	for path in TOLL_TICK_PATHS:
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			break
	if stream == null:
		return
	if _toll_tick_player == null:
		_toll_tick_player = AudioStreamPlayer.new()
		_toll_tick_player.bus = &"SFX"
		add_child(_toll_tick_player)
	_toll_tick_player.stream = stream
	_toll_tick_player.volume_db = toll_tick_volume_db
	_toll_tick_player.play()

func _screen_pos_for_damage_target(target: Variant) -> Vector2:
	if target is FieldEnemy:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			return camera.unproject_position((target as FieldEnemy).global_position + Vector3.UP * enemy_head_height)
	# "player" (or anything else without a 3D position this overlay can
	# reach) - anchor near the field HP bar instead of unprojecting a
	# Wanderer position this overlay has no reference to.
	return _field_hp_bar.global_position + Vector2(_field_hp_bar.size.x / 2.0, _field_hp_bar.size.y + 20.0)

# The debug row's WIN/LOSE/ESCAPE: the same ending, marked as not the
# fight's own (finished_by_debug) for the run log.
func _finish_debug(outcome: Outcome) -> void:
	finished_by_debug = true
	_finish_battle(outcome)

# Every CardData in debug_card_dirs, by card name, each item carrying its
# card as metadata.
func _fill_debug_card_picker() -> void:
	var cards: Array[CardData] = []
	for dir in debug_card_dirs:
		for file in ResourceLoader.list_directory(dir):
			if not file.ends_with(".tres"):
				continue
			var card := load(dir.path_join(file)) as CardData
			if card != null:
				cards.append(card)
	cards.sort_custom(func(a: CardData, b: CardData) -> bool: return a.card_name.naturalnocasecmp_to(b.card_name) < 0)
	for card in cards:
		_debug_card_picker.add_item(card.card_name)
		_debug_card_picker.set_item_metadata(_debug_card_picker.item_count - 1, card)

# The picked card into the run's deck (RunState.add_card(), so it outlasts
# the fight) and that same copy into this fight - the hand, or the top of
# the draw pile when the hand is full (Deck.add(), never a draw). The
# same instance in both, so a CONSUMED play still takes it out of the run
# at the fight's end. Logged, so a run that used it can be left out of
# tuning.
func _on_debug_add_card_pressed() -> void:
	if battle_controller == null or battle_controller.deck == null or _debug_card_picker.selected < 0:
		return
	var card := _debug_card_picker.get_item_metadata(_debug_card_picker.selected) as CardData
	if card == null:
		return
	battle_controller.deck.add(RunState.add_card(card))
	RunLogger.event("debug_card_add", {"card": card.card_name, "context": "battle"})

# Debug builds only: one more Energy this turn, past max if need be, told
# through the controller's own energy_changed (the readout, the hand's
# playable faces). Logged, so a run that used it can be left out of
# tuning.
func _on_debug_add_energy_pressed() -> void:
	if battle_controller == null or battle_controller.player == null:
		return
	battle_controller.player.energy += 1
	battle_controller.energy_changed.emit(battle_controller.player.energy)
	RunLogger.event("debug_energy_add", {})

# The one path every battle-ending trigger (WIN/LOSE/ESCAPE debug buttons,
# battle_controller.battle_won/battle_lost) now goes through, rather than
# emitting battle_finished directly - the field readouts have to leave
# battle style (and the field DeckPanel come back) before region_field.gd
# reacts to battle_finished and frees this overlay.
func _finish_battle(outcome: Outcome) -> void:
	_field_hp_bar.hide_toll()
	# Grace is per fight (it lives on the Combatant, which this battle's
	# end discards) - the segment goes with it whatever the outcome.
	_field_hp_bar.hide_grace()
	# Stances and statuses are per fight, like Grace - the row goes with
	# them whatever the outcome.
	_field_hp_bar.clear_standing_row()
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
		# What a hover reveal has to fit in: from a one-line status row's
		# bottom to the resting cards.
		print("BattleOverlay: enemy '%s' status row bottom-to-hand gap = %.1f px" % [enemy.enemy_id, hand_container.get_rest_top_y() - status.get_status_row_bottom_y()])
	if _field_hp_bar != null:
		var hp_bottom: float = (_field_hp_bar.get_global_transform() * Vector2(0.0, _field_hp_bar.size.y)).y
		print("BattleOverlay: Wanderer HP readout bottom-to-hand gap = %.1f px" % (hand_container.get_rest_top_y() - hp_bottom))
		print("BattleOverlay: Wanderer status row bottom-to-hand gap = %.1f px" % (hand_container.get_rest_top_y() - _field_hp_bar.get_status_row_bottom_y()))

func _spawn_floating_number(value: int, screen_pos: Vector2, size_multiplier: float = 1.0) -> void:
	var number := (load(FLOATING_NUMBER_SCENE_PATH) as PackedScene).instantiate() as FloatingNumber
	add_child(number)
	number.show_value(value, screen_pos, size_multiplier)

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
	if _keepsake_row != null:
		_keepsake_row.refresh_style()
	end_turn_button.refresh_style()
	print("BattleOverlay: ui_on_dark_world (debug flip) = %s" % str(_on_dark_world))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			debug_row.visible = not debug_row.visible
			if debug_row.visible and _debug_card_picker.item_count == 0:
				_fill_debug_card_picker()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F2:
			_flip_dark_world()
			get_viewport().set_input_as_handled()
