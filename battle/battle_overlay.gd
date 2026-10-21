extends Control
class_name BattleOverlay

const FLOATING_NUMBER_SCENE_PATH := "res://battle/floating_number.tscn"
# A mound's plate is an enemy plate in its mound mode (EnemyStatus.set_mound()).
const MOUND_PLATE_SCENE_PATH := "res://battle/enemy_status.tscn"
const CARD_PLAY_SFX_PATH := "res://assets/audio/ui/card_played.mp3"
const CARD_DRAW_SFX_PATH := "res://assets/audio/ui/card_draw.wav"
# Draw-sound voices, oldest stolen: a turn's draw launches a card every
# 0.07 s and the take rings 0.4 s, so about six overlap. Each voice its
# own player, so one card's pitch jitter never bends another's.
const CARD_DRAW_VOICES := 6
# Devour's bite (BattleController.card_devoured), one take a time, never
# the same one twice running - see _on_card_devoured().
const DEVOUR_SFX_PATHS: Array[String] = [
	"res://assets/audio/sfx/devour/devour_01.mp3",
	"res://assets/audio/sfx/devour/devour_02.mp3",
]
# The Devour keyword's sound (BattleController.keyword_devoured - Take In),
# once per card eaten; never the Devour button's bite above.
const DEVOUR_KEYWORD_SFX_PATH := "res://assets/audio/sfx/devour/devour_keyword.wav"

enum Outcome { WIN, LOSE, ESCAPE }

signal battle_finished(outcome: Outcome)

@export var enemy_head_height: float = 1.8
# The Wanderer's numbers sit this far, in pixels, over the top of his
# model (Wanderer.get_head_height()) - clear of his HP bar under his feet.
@export var wanderer_number_over_head_px: float = 10.0
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
# A further hit's number on a target whose last still shows - a multi-hit
# ("5, 5, 5") - steps this far on from the one before, in screen pixels,
# so each reads as its own blow. The player's and the enemies' alike.
@export var number_stack_step: Vector2 = Vector2(30.0, -38.0)
# A number keeps this far, in pixels, off its own readouts the whole way it
# rises - an enemy's intent and HP/name plate, his HP bar - moved beside
# them when it would cross.
@export var number_clearance_px: float = 8.0
# A mound's number sits this far, in pixels, over the top of the mound's
# screen bounds (FieldEnemy.get_mound_screen_rect()).
@export var number_over_body_px: float = 10.0
# An enemy's number starts at mid-body: its bottom this fraction of the way
# down its body's screen bounds (FieldEnemy.get_screen_rect()) from their
# top - on the body it happened to, tall (the Wardling's lantern) or low
# (a crab) alike, and below the intent over its head; at enemy_head_height
# when there are no bounds to read.
@export_range(0.0, 1.0) var number_body_fraction: float = 0.5
# While a number over an enemy (or its mounds) shows, that enemy's intent
# fades to this, its marks with it - back as the number fades
# (_dim_intents_under_numbers()).
@export_range(0.0, 1.0) var intent_dim_alpha: float = 0.4
# Readouts (plates, intents, his HP bar) are pushed apart until this many
# pixels lie between any two (_lay_out_readouts()).
@export var readout_gap_px: float = 4.0
# What a refused intent says while an armed Brace or Garnish hovers it
# (_sync_armed_intents(); %s is the intent's name), read live: one landing
# as a strike back (the Erupt); not an attack; Denied, a pain turn's or an
# interrupted one; and one already carrying the card's mark, by mark.
@export var mark_refusal_only_block: String = "%s: only Block reduces it."
@export var mark_refusal_not_attack: String = "%s: not an attack."
@export var mark_refusal_wont_land: String = "%s: it won't land."
@export var mark_refusal_already: Dictionary = {&"brace": "Already braced.", &"garnish": "Already garnished.", &"wrest": "Already wrested."}
# What hovering an intent says, at any time (_intent_hover_text()), one
# line in system voice beneath it - while a Brace or Garnish is armed its
# validity lines (above) take the refused ones' place. By what the intent
# is; %s and %d as each line's own. Read live.
@export var intent_hover_lines: Dictionary = {
	&"attack": "%s: deals %s.",
	# A marked attack (Braced, Garnished on it): what it would deal, each
	# mark with what it takes, then the hits that land - "Tail Lash: 5×3,
	# Braced (halved), Garnished (5 less in all) — 0, 0, 1: 1 in all."
	&"marked": "%s: %s, %s — %s.",
	&"lands_hits": "%s: %d in all",
	&"mark_halved": "%s (halved)",
	&"mark_less_percent": "%s (%d%% less)",
	&"mark_more_percent": "%s (%d%% more)",
	&"mark_less_in_all": "%s (%d less in all)",
	&"hits": "%d×%d",
	&"total": "%d over %d hits",
	&"twice": "%s twice",
	&"applies": " Then %s %d.",
	&"threshold": " Deal %d to it this turn to break it.",
	&"strike_back": "%s: %d from below as your turn ends; only Block reduces it.",
	&"defend": "%s: gains %d Block.",
	&"defend_twice": "%s: gains %d Block, twice.",
	&"heal": "%s: heals its pack %d.",
	&"brings": "%s: %s until its next %s. While %s, %s",
	&"brings_next": "%s (%d)",
	&"brings_any": "move",
	&"taunts": "your single-target Attacks must hit it",
	&"half_damage": "for half damage",
	&"less_damage": "for %d%% less damage",
	&"more_damage": "for %d%% more damage",
	&"signal": "%s: %s %s; each answers with %s %d (%d in all).",
	&"signal_mixed": "%s: %s %s; they answer with %s (%d in all).",
	&"signal_wakes": "wakes",
	&"signal_calls": "calls",
	&"signal_none": "%s: calls a pack that isn't there.",
	&"dig": "%s: goes under its mounds; next it %s for %d unless you break the one it's under.",
	&"holds": " While queued, %s: %s",
	&"burrow": "%s: goes under; it can't be targeted until it surfaces.",
	&"watch": "%s: watches.",
	&"plain": "%s.",
	&"cancelled": "%s: cancelled; it won't act.",
	&"denied": "%s: stunned; it won't act.",
	&"delayed": "%s: delayed; it acts next turn.",
	&"broken": "%s: broken; it won't land.",
}
# The draw sound, once per card as it leaves the deck (HandContainer.
# draw_started): a -6 dBFS take at -22, 6 dB under card play, so a
# five-card draw is felt rather than loud. One take only (see DESIGN.md),
# so each play's pitch moves by up to +-this fraction instead of a
# round-robin. Both read at each play, so a Remote-tab edit applies from
# the next card.
@export var card_draw_volume_db: float = -22.0
@export_range(0.0, 0.5) var card_draw_pitch_jitter: float = 0.05
# Devour's bite, a 2D UI sound: its takes peak at -6.6 and -6.0 dBFS, so
# -10 here lands them about -16 at the listener. Read at each bite.
@export var devour_volume_db: float = -10.0
# The Devour keyword's sound, a 2D UI sound like the bite: a -6 dBFS take
# at card play's level (card_play_volume_db) to start. Read at each card
# eaten.
@export var devour_keyword_volume_db: float = -16.0
# The battle sand puffs' tint (BattleFeedback.sand_puff_tint), set here as
# BattleFeedback is built in code (enter_battle()); passed on live.
@export var sand_puff_tint: float = 0.75:
	set(value):
		sand_puff_tint = value
		if _battle_feedback != null:
			_battle_feedback.sand_puff_tint = value

@export_group("Choice Prompt")
# An open hand choice says what it wants in one tracked-caps ink line,
# this far above the armed card, or above the hand for the end-of-turn
# keep (BattleController.hand_choice_*): its verb (KEEP) and how many cards are left to pick (choice_prompt_format), then,
# for a choice confirmed elsewhere, what to click (choice_confirm_format -
# END TURN, the keep's). A choice that takes a variable count (Bide's)
# has a DONE beside the line, in the same ink as End Turn; one with a
# fixed count goes on by itself at its last pick and has neither.
@export var choice_prompt_format: String = "%s  ·  %d LEFT"
@export var choice_confirm_format: String = "  ·  CLICK %s TO CONFIRM"
@export var choice_done_text: String = "DONE":
	set(value):
		choice_done_text = value
		if _choice_done != null:
			_choice_done.text = value
			_choice_done.refresh_style()
# Between the prompt line's end and DONE.
@export var choice_done_gap_px: float = 18.0
@export var choice_prompt_font_size_px: int = 13:
	set(value):
		choice_prompt_font_size_px = value
		_style_choice_prompt()
@export var choice_prompt_tracking_em: float = 0.16:
	set(value):
		choice_prompt_tracking_em = value
		_style_choice_prompt()
@export var choice_prompt_gap_px: float = 12.0

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
# The whole bottom-left stack - the energy readout, Devour under it and
# the line over it (the pick's prompt, the keepsake reveal) - raised this
# far above energy_anchor, so a hovered card clears Devour too. With
# energy_group_offset's 12 px down, Devour's bottom (750.4 at 1080p) sits
# 12 px over the leftmost card hovered at full size - 762.4 at five to
# eight in hand, the tightest; the hand fills its limits from eight, so
# that card is always under the column. devour_probe checks it.
@export var energy_stack_lift_px: float = 68.0:
	set(value):
		energy_stack_lift_px = value
		_apply_energy_anchor()
# Devour (DevourButton) stands on its own above the energy readout: its
# left edge on the corner margin (corner_margin_px), its bottom this many
# px over the energy numeral's ink top - clear of the pips and the hand.
@export var devour_gap_px: float = 30.0:
	set(value):
		devour_gap_px = value
		_apply_energy_anchor()
# The energy group - readout and Devour - moved as one from where
# energy_anchor and energy_stack_lift_px put it, in overlay (1080p) px
# like every corner readout, so it scales with the HUD. 12 px down keeps
# the leftmost hovered card 12 px under Devour (see energy_stack_lift_px).
# The overlay scene sets x to -246.75: the group's right edge (214.75)
# 12 px left of a hovered card at seven in hand, so nothing at seven or
# fewer reaches its column, and clear of the second card at eight to ten.
@export var energy_group_offset: Vector2 = Vector2(-40.0, 12.0):
	set(value):
		energy_group_offset = value
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
	"res://cards/samurai/",
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
# A number's whole life and its legible part (pop and hold), read once
# (_read_number_times()); -1 until then.
var _number_life: float = -1.0
var _number_legible: float = -1.0
# Target (a FieldEnemy, or "player") -> how many of its numbers show now,
# for the stack's step (number_stack_step).
var _number_counts: Dictionary = {}
# Target -> the sideways jitter its stack's first number drew - the rest of
# the stack share it, so the step stays exact.
var _stack_jitter: Dictionary = {}
# The Wanderer, for his numbers' anchor (_screen_pos_for_damage_target()).
var _wanderer: Wanderer = null
var _enemy_statuses: Dictionary = {} # FieldEnemy -> EnemyStatus
# A dug-in enemy's mounds' plates (EnemyStatus.set_mound()), made and
# dropped as its row stands (_sync_mound_plates()) - children of this
# overlay, gone with the fight. _mound_key() -> EnemyStatus.
var _mound_plates: Dictionary = {}
# One BattleIntent per enemy for this fight - children of this overlay,
# so they're freed with it and nothing of them exists on the field.
var _enemy_intents: Dictionary = {} # FieldEnemy -> BattleIntent
# FieldEnemy -> the FloatingNumbers showing over it (and its mounds) now,
# for its intent's dim (_dim_intents_under_numbers()).
var _numbers_over: Dictionary = {}
# A card that marks intents (Brace, Garnish) armed now, or null - its
# targets' hairlines and the refused ones' fade (_sync_armed_intents()).
var _armed_marking: CardData = null
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
# The card whose cost the energy pips preview (HandContainer.cost_focus_
# changed), and whether a play is holding the preview until its spend
# lands - see _on_cost_focus_changed().
var _cost_focus: CardData = null
var _cost_preview_held: bool = false
# The HP bar's preview of the same card's HP cost holds from the play's
# commit until the card has resolved and its losses have landed
# (BattleController.play_resolved) - later than the pips, whose Energy is
# spent at the commit. See _refresh_hp_cost_preview().
var _hp_preview_held: bool = false
var _card_draw_players: Array[AudioStreamPlayer] = []
var _card_draw_next: int = 0
# The per-card override's player, made on first use - see _on_card_played().
var _card_override_player: AudioStreamPlayer = null
# Devour's player and its takes (DEVOUR_SFX_PATHS, those that load), made
# on the first bite; the take it played last (-1: none yet).
var _devour_player: AudioStreamPlayer = null
var _devour_takes: Array[AudioStream] = []
var _devour_last_take: int = -1
# The Devour keyword's player, made on the first card it eats.
var _devour_keyword_player: AudioStreamPlayer = null
var _resources: BattleResources = null
var _deck_readout: DeckPanel = null
var _discard_readout: DeckPanel = null
var _keepsake_row: KeepsakeRow = null
var _devour_button: DevourButton = null
# The energy readout and Devour under it, as one group (_create_corner_
# readouts()): placed as a whole by _apply_energy_anchor(), their own
# layout inside it. Ignores the mouse, so it never stands in front of a
# card - the two in it take their own clicks.
var _energy_group: Control = null
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
# The open choice's DONE (choice_done_text), made with the first choice
# that has one; hidden while none is open or the open one has none.
var _choice_done: EndTurnButton = null

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
	_wanderer = wanderer

	_field_hp_bar = field_hp_bar
	_field_hp_bar.enter_battle(battle_transition_time)
	# Toll is the floor's, not the fight's: it opens on what was carried in.
	# A class without Toll (CharacterData.has_toll) shows none - and
	# HPBar's updates are no-ops while it isn't shown.
	if RunState.character != null and RunState.character.has_toll:
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
	# A devoured card slides into the jaw.
	hand_container.set_devour_target(_devour_button)

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
	battle_controller.mound_damaged.connect(_on_mound_damaged)
	battle_controller.mound_broken.connect(func(enemy: FieldEnemy, mound: int, own: bool) -> void:
		if _battle_feedback != null:
			_battle_feedback.on_mound_broken(enemy, mound, own)
	)
	battle_controller.combat_text.connect(_show_number)
	# A hit a block took whole shows BLOCKED on whoever's block it was.
	battle_controller.enemy_hit_blocked.connect(func(enemy: FieldEnemy, absorbed: bool) -> void:
		if absorbed:
			_show_number(enemy, 0, FloatingNumber.KIND_BLOCKED))
	battle_controller.player_hit_blocked.connect(func(_enemy: FieldEnemy) -> void:
		_show_number("player", 0, FloatingNumber.KIND_BLOCKED))
	battle_controller.enemy_intent_changed.connect(_on_enemy_intent_changed)
	battle_controller.energy_changed.connect(hand_container.update_playable)
	battle_controller.energy_changed.connect(_on_energy_changed)
	hand_container.cost_focus_changed.connect(_on_cost_focus_changed)
	# A play holds the outlined pips until its energy_changed turns them
	# spent.
	battle_controller.card_played.connect(func(_card: CardData, _target: FieldEnemy) -> void: _cost_preview_held = true)
	battle_controller.card_played.connect(func(_card: CardData, _target: FieldEnemy) -> void:
		_hp_preview_held = true
		if _field_hp_bar != null:
			_field_hp_bar.hold_cost_preview())
	battle_controller.play_resolved.connect(func(_card: CardData) -> void:
		_hp_preview_held = false
		_refresh_hp_cost_preview())
	battle_controller.status_changed.connect(_on_status_changed)
	battle_controller.turn_phase_changed.connect(_on_turn_phase_changed)
	battle_controller.enemy_acting.connect(_on_enemy_acting)
	battle_controller.enemy_defeated.connect(_on_enemy_defeated)
	battle_controller.battle_won.connect(func() -> void: _finish_battle(Outcome.WIN))
	battle_controller.battle_lost.connect(func() -> void: _finish_battle(Outcome.LOSE))
	hand_container.armed_changed.connect(_on_card_armed_changed)
	# Devour's pick greys End Turn the way an armed card does.
	battle_controller.devour_changed.connect(func(_available: bool, _used: bool) -> void: _update_end_turn())
	battle_controller.entry_lock_changed.connect(func(_locked: bool) -> void: _update_end_turn())
	if _devour_button != null:
		_devour_button.setup(battle_controller)
	# A devoured card is out of the hand: the cursor back, and the faces
	# that read the hand re-read.
	battle_controller.card_devoured.connect(func(_card: CardData) -> void:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_play_devour_take()
		_push_bonus_context())
	battle_controller.keyword_devoured.connect(func(_card: CardData) -> void: _play_devour_keyword())
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
	# Collateral's "-N HP" depends on the Energy held: the faces re-read it.
	battle_controller.energy_changed.connect(func(_energy: int) -> void: _push_bonus_context())
	# A status taken (Keen, a keepsake's) moves every Attack's printed damage.
	battle_controller.status_changed.connect(func() -> void: _push_bonus_context())
	# The armed card's damage reads against the enemy under the cursor.
	battle_controller.hovered_enemy_changed.connect(_on_hovered_enemy_changed)
	battle_controller.setup(hand_container, enemy_list, wanderer)
	_push_bonus_context()
	get_tree().create_timer(battle_transition_time).timeout.connect(_reveal_enemy_intents)

	_battle_feedback = BattleFeedback.new()
	_battle_feedback.sand_puff_tint = sand_puff_tint
	add_child(_battle_feedback)
	_battle_feedback.setup(wanderer, on_dark_world)
	_battle_feedback.battle_controller = battle_controller
	battle_controller.kill_presentation_time = _kill_presentation_time
	battle_controller.intent_rect_of = _intent_rect_of
	battle_controller.damage_dealt.connect(_battle_feedback.on_damage_dealt)
	battle_controller.enemy_hit_blocked.connect(_battle_feedback.on_enemy_hit_blocked)
	battle_controller.player_hit_blocked.connect(_battle_feedback.on_player_hit_blocked)
	# A card's play effect (Blood Arc's stroke) goes down before its hits
	# report, over the enemies it can hit - and under their intent
	# readouts, the lowest of whose bottom edges it is handed.
	battle_controller.card_impact.connect(func(card: CardData) -> void:
		_battle_feedback.on_card_impact(card, battle_controller.enemies, _lowest_intent_height()))

	_deck_readout.bind_to_deck(battle_controller.deck, DeckPanel.Pile.DRAW)
	_discard_readout.bind_to_deck(battle_controller.deck, DeckPanel.Pile.DISCARD)
	_refresh_keepsake_row()
	RunState.keepsake_changed.connect(func(_keepsake: TrinketData) -> void: _refresh_keepsake_row())
	RunState.worn_changed.connect(func(_worn: TrinketData) -> void: _refresh_keepsake_row())
	_layout_corners()

	var target_line := TargetLine.new()
	add_child(target_line)
	target_line.setup(battle_controller)
	target_line.set_devour_button(_devour_button)

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
	_energy_group = Control.new()
	_energy_group.name = "EnergyGroup"
	_energy_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_energy_group)
	_resources = BattleResources.new()
	_energy_group.add_child(_resources)
	# Its size changes with the numeral and the tally; the right edge and
	# the numeral's top hold.
	_resources.resized.connect(_apply_energy_anchor)
	_deck_readout = DeckPanel.new()
	add_child(_deck_readout)
	_discard_readout = DeckPanel.new()
	_discard_readout.align_right = true
	add_child(_discard_readout)
	# A pile's view is over the battle but lets it show through its scrim:
	# the hand goes while one is open, so it never reads through the view.
	for readout: DeckPanel in [_deck_readout, _discard_readout]:
		readout.view_opened.connect(_on_pile_view_opened)
		readout.view_closed.connect(_on_pile_view_closed)
	_keepsake_row = KeepsakeRow.new()
	add_child(_keepsake_row)
	# A class without Devour (CharacterData.has_devour) gets no button; the
	# stack's top is then the energy numeral's.
	if RunState.character != null and not RunState.character.has_devour:
		return
	_devour_button = DevourButton.new()
	_devour_button.name = "DevourButton"
	# Its own place, above the energy readout - not in the energy group.
	add_child(_devour_button)
	_devour_button.resized.connect(_apply_energy_anchor)

# The keepsakes with no in-combat counter go in the row under DECK; one
# whose status counts is a counter line under the HP bar instead (see
# _refresh_standing_row()). The keepsake slot, then the worn piece beside
# it (RunState.held_pieces()).
func _refresh_keepsake_row() -> void:
	var quiet: Array[TrinketData] = []
	for piece in RunState.held_pieces():
		var status: StatusData = piece.combat_start_status
		if status == null or status.self_loss_trigger_count <= 0:
			quiet.append(piece)
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
# numeral's top energy_stack_lift_px over the anchor's y, whatever the
# readout's size. The keepsake row's hover text keeps to the readout's top
# row, so it never lands on the readout.
func _apply_energy_anchor() -> void:
	if _resources == null or _energy_group == null:
		return
	# The group goes where the readout's top-left goes; inside it the
	# readout sits at its origin and Devour under it.
	_energy_group.position = Vector2(maxf(energy_anchor.x - _resources.size.x, corner_margin_px), energy_anchor.y - energy_stack_lift_px - _resources.numeral_ink_top()) + energy_group_offset
	_resources.position = Vector2.ZERO
	# The stack's top, where the hover lines go over: the energy numeral's,
	# or Devour's above it.
	var stack_top: float = _resources.global_position.y
	# Devour on its own above the readout: the corner margin, its bottom
	# devour_gap_px over the numeral's ink top.
	if _devour_button != null:
		var numeral_top: float = _energy_group.position.y + _resources.numeral_ink_top()
		_devour_button.position = Vector2(corner_margin_px, numeral_top - devour_gap_px - _devour_button.size.y)
		stack_top = _devour_button.position.y
		_devour_button.set_hover_floor_y(stack_top)
	if _keepsake_row != null:
		_keepsake_row.set_reveal_floor_y(stack_top)
	_energy_group.size = _energy_group_extent()
	# The Wanderer's HP row keeps its distance from the group's right edge
	# (HPBar.min_energy_clearance_px).
	if _field_hp_bar != null:
		_field_hp_bar.set_energy_clearance_x(_energy_group.get_global_rect().end.x)

# The group's own size: the energy readout (Devour stands apart).
func _energy_group_extent() -> Vector2:
	return _resources.size

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

# The bar moves with the hit's number: when a play effect paces the hit
# (BattleFeedback.reaction_delay() - Blood Arc's stroke reaching it), it
# waits as long, read in the hit's own frame.
func _on_enemy_hp_changed(enemy: FieldEnemy, current: int, max_hp: int) -> void:
	var delay: float = _battle_feedback.reaction_delay(enemy) if _battle_feedback != null else 0.0
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if not is_instance_valid(enemy):
			return
	var status: EnemyStatus = _enemy_statuses.get(enemy)
	if status != null:
		status.update_hp(current, max_hp)

func _create_enemy_intents(enemy_list: Array[FieldEnemy]) -> void:
	for enemy in enemy_list:
		var intent := BattleIntent.new()
		add_child(intent)
		intent.set_target(enemy)
		_enemy_intents[enemy] = intent

# Every enemy readout on screen now - its HP/name plate and its intent -
# as screen rects (BattleOcclusion fades what lies under them).
func get_readout_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for display in _enemy_statuses.values() + _enemy_intents.values() + _mound_plates.values():
		var control := display as Control
		if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		var rect: Rect2 = control.get_global_rect()
		if rect.has_area():
			rects.append(rect)
	return rects

# `enemy`'s intent readout on screen (BattleIntent.get_pair_global_rect()),
# for a card aimed at intents: empty while it shows nothing.
func _intent_rect_of(enemy: FieldEnemy) -> Rect2:
	var intent: BattleIntent = _enemy_intents.get(enemy)
	if intent == null or not is_instance_valid(intent) or not intent.is_visible_in_tree():
		return Rect2()
	return intent.get_pair_global_rect()

# Once the camera swing/stance step has settled - the same delay HPBar/
# EnemyStatus's style tween takes - every display with an intent shows.
func _reveal_enemy_intents() -> void:
	_intents_revealed = true
	# The fight's opening Block (the held pieces') shows as the frame settles.
	if battle_controller != null and battle_controller.opening_block_gained > 0:
		_show_number("player", battle_controller.opening_block_gained, FloatingNumber.KIND_BLOCK)
	for intent: BattleIntent in _enemy_intents.values():
		if is_instance_valid(intent):
			intent.set_revealed(true)

# After setup, after each card resolves, at each turn start, and right
# after an enemy has acted (its NEXT action) - see BattleController's own
# signal doc. A display hidden for the enemy's action takes its new
# intent here, and shows again once the enemy turn is over (_enemy_phase).
func _on_enemy_intent_changed(enemy: FieldEnemy, preview: Dictionary) -> void:
	# Its Dig queued: the sand sprays at it until it goes under.
	if is_instance_valid(enemy):
		enemy.set_dig_spray(int(preview.get("type", -1)) == EnemyIntent.IntentType.DIG and not bool(preview.get("denied", false)) and not bool(preview.get("delayed", false)) and not bool(preview.get("pain_turn", false)))
	var intent: BattleIntent = _enemy_intents.get(enemy)
	if intent == null or not is_instance_valid(intent):
		return
	intent.show_intent(preview)
	if _intents_revealed and not _enemy_phase:
		intent.set_revealed(true)

# The pile views open over the battle (DRAW / DISCARD): the hand hidden
# while any is.
var _pile_views_open: int = 0

func _on_pile_view_opened() -> void:
	_pile_views_open += 1
	hand_container.visible = false

func _on_pile_view_closed() -> void:
	_pile_views_open = maxi(_pile_views_open - 1, 0)
	if _pile_views_open == 0:
		hand_container.visible = true

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
	_refresh_hp_cost_preview()
	if _resources == null or battle_controller == null or battle_controller.player == null:
		return
	if _cost_preview_held:
		return
	var cost: int = 0
	# A card armed for Devour alone isn't going to be paid for.
	if _cost_focus != null and not battle_controller.is_armed_for_devour_only():
		cost = battle_controller.player.energy_cost(_cost_focus)
		if cost > battle_controller.player.energy:
			cost = 0
	_resources.set_cost_preview(cost)

# The same card's HP cost on the HP bar - every HP playing it now will
# take (CardBonus.predicted_self_loss(), which its face's badge reads
# too), and only when it can be paid, as the pips. Re-read whenever the
# hand's faces are (_push_bonus_context() - HP, statuses, stance, Energy,
# Grace, the turn), so it previews the fight as it stands. A play holds
# what it showed until play_resolved.
func _refresh_hp_cost_preview() -> void:
	if _field_hp_bar == null or battle_controller == null or battle_controller.player == null:
		return
	if _hp_preview_held:
		return
	var loss: int = 0
	if _cost_focus != null and not battle_controller.is_armed_for_devour_only() and battle_controller.player.can_pay(_cost_focus):
		loss = CardBonus.predicted_self_loss(_cost_focus, battle_controller.preview_context())
	_field_hp_bar.set_cost_preview(loss)

func _on_toll_changed(new_toll: int) -> void:
	# A gain counts up and shows its "+N" at the readout (HPBar.update_toll()).
	_field_hp_bar.update_toll(new_toll)
	# A TOLL_HEAL prints a number made of Toll.
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
		lines.append({"text": stance_text, "glyph": &"stance", "name": stance.data.display_name, "rules": stance.describe()})
	var chain: Dictionary = _chain_line(player)
	if not chain.is_empty():
		lines.append(chain)
	var counters: Array[Dictionary] = []
	for active: Status in player.statuses:
		if active.data == null:
			continue
		var line: Dictionary = {"text": active.label(), "name": active.data.display_name, "rules": active.describe(player)}
		# Its mark before the label (Venom's drop).
		if active.data.mark == StatusData.Mark.DROP:
			line["glyph"] = &"drop"
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
	_field_hp_bar.set_standing_row(lines)
	_field_hp_bar.set_hand_top_y(hand_container.get_rest_top_y())

# The row's chain line (Skillchain): "Chain 2 · Parry" - the level, then
# the last skillchain this chain fired, once one has - or {} with no
# chain. Its reveal says what extends it and what that fires, by the
# player's own numbers (Skillchain.payoff()). Read whenever the row is:
# after a play, and on the status_changed that follows each turn's reset.
func _chain_line(player: Combatant) -> Dictionary:
	if player.chain_property == CardData.ChainProperty.NONE:
		return {}
	var text: String = "Chain %d" % player.chain_level
	if player.last_skillchain != &"":
		text += " · %s" % player.last_skillchain
	var next: CardData.ChainProperty = Skillchain.next_property(player.chain_property)
	var level: int = player.chain_level + 1
	var link: StringName = Skillchain.link_into(next)
	var payoff: CardEffect = Skillchain.payoff(link, level, player)
	var amount: int = payoff.value if payoff != null else 0
	var fires: String = ""
	match link:
		Skillchain.PARRY:
			fires = "Parry for %d Block" % amount
		Skillchain.RECOVER:
			fires = "Recover, drawing %d" % amount
		Skillchain.LUNGE:
			fires = "Lunge for %d damage to its target" % amount
	var property: String = str(CardData.ChainProperty.find_key(next)).capitalize()
	var rules: String = "%s next: chain %d, %s. Any other card ends the chain." % [property, level, fires]
	return {"text": text, "name": "Chain", "rules": rules}

# Block moved somewhere (a card, a turn start, an enemy's own guard) -
# every readout's segment follows. So does the player's Critical line,
# which a status can raise for the fight (Combatant.critical_fraction() -
# Gone Under): the HP bar's tick and colour, and the Critical keyword's
# tooltip.
func _on_status_changed() -> void:
	_field_hp_bar.set_block(battle_controller.player.block)
	var critical_line: float = battle_controller.player.critical_fraction()
	_field_hp_bar.set_critical_fraction(critical_line)
	KeywordTable.fight_critical_fraction = critical_line
	_refresh_standing_row()
	for enemy: FieldEnemy in _enemy_statuses:
		var status: EnemyStatus = _enemy_statuses[enemy]
		if status != null and is_instance_valid(status):
			status.set_block(battle_controller.get_enemy_block(enemy))
			status.set_status_row(battle_controller.get_enemy_status_labels(enemy))
			var intent: BattleIntent = _enemy_intents.get(enemy)
			if intent != null and is_instance_valid(intent):
				intent.set_countdowns(battle_controller.get_enemy_countdowns(enemy))
			# Beside its HP: the one status shown there (Coiled), mark and
			# magnitude - or nothing.
			var beside: Status = battle_controller.get_enemy_hp_mark_status(enemy)
			if beside != null and beside.data.mark == StatusData.Mark.COIL:
				status.set_hp_mark(&"coil", beside.magnitude)
			else:
				status.set_hp_mark(&"", 0)
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
	_refresh_hp_cost_preview()

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
	var picking: bool = battle_controller != null and battle_controller.is_devour_picking()
	var opening: bool = battle_controller != null and battle_controller.is_entry_locked()
	end_turn_button.set_enabled(_player_turn and not _card_armed and not picking and not opening)

# `confirm_label`: what confirms the choice when that's something else
# (END TURN), empty when DONE or the last pick does; `done`: whether it
# has a DONE.
func _on_hand_choice_started(confirm_label: String, _cap: int, verb: String, done: bool) -> void:
	_choice_card_name = confirm_label
	_choice_verb = verb
	if _choice_prompt == null:
		_choice_prompt = Label.new()
		_choice_prompt.name = "ChoicePrompt"
		_choice_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_choice_prompt)
	_style_choice_prompt()
	_choice_prompt.visible = true
	if done and _choice_done == null:
		_choice_done = EndTurnButton.new()
		_choice_done.name = "ChoiceDone"
		_choice_done.label_text = choice_done_text
		add_child(_choice_done)
		_choice_done.pressed.connect(func() -> void: battle_controller.confirm_choice())
	if _choice_done != null:
		_choice_done.visible = done

func _on_hand_choice_changed(marked: int, cap: int) -> void:
	if _choice_prompt == null:
		return
	var line: String = choice_prompt_format % [_choice_verb, maxi(cap - marked, 0)]
	if _choice_card_name != "":
		line += choice_confirm_format % _choice_card_name.to_upper()
	_choice_prompt.text = line
	_choice_prompt.size = Vector2.ZERO
	_place_choice_prompt()

func _on_hand_choice_ended() -> void:
	_choice_card_name = ""
	if _choice_prompt != null:
		_choice_prompt.visible = false
	if _choice_done != null:
		_choice_done.visible = false

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
	# The line and its DONE centred as one.
	var done_shown: bool = _choice_done != null and _choice_done.visible
	var width: float = _choice_prompt.size.x
	if done_shown:
		width += choice_done_gap_px + _choice_done.size.x
	var left: float = centre_x - width / 2.0
	_choice_prompt.global_position = Vector2(left, top_y - choice_prompt_gap_px - _choice_prompt.size.y)
	if done_shown:
		_choice_done.global_position = Vector2(left + _choice_prompt.size.x + choice_done_gap_px, _choice_prompt.global_position.y + (_choice_prompt.size.y - _choice_done.size.y) / 2.0)

func _process(_delta: float) -> void:
	_place_choice_prompt()
	_sync_mound_plates()
	_lay_out_readouts()
	_sync_armed_intents()
	_dim_intents_under_numbers()

# Each intent dims under the numbers over its enemy: intent_dim_alpha at
# a number's full ink, back up with it as it fades (FloatingNumber's own
# fade), whole once none is left.
func _dim_intents_under_numbers() -> void:
	for enemy: Variant in _numbers_over.keys():
		var strongest: float = 0.0
		var alive: Array = []
		for number: Variant in _numbers_over[enemy]:
			if is_instance_valid(number) and not (number as Node).is_queued_for_deletion():
				alive.append(number)
				strongest = maxf(strongest, (number as CanvasItem).modulate.a)
		var intent: BattleIntent = _enemy_intents.get(enemy)
		if intent != null and is_instance_valid(intent):
			intent.set_number_dim(lerpf(1.0, clampf(intent_dim_alpha, 0.0, 1.0), clampf(strongest, 0.0, 1.0)))
		if alive.is_empty():
			_numbers_over.erase(enemy)
		else:
			_numbers_over[enemy] = alive

# While a card that marks intents (Brace, Garnish) is armed: each intent
# it may target gets its hairline, each it may not fades, and the refused
# one under the cursor says why (mark_refusal_*). Every frame, so a play
# or an intent changing under it is caught; nothing armed, nothing shown.
func _sync_armed_intents() -> void:
	if battle_controller == null:
		return
	var view: CardView = battle_controller.get_pending_card_view()
	var card: CardData = view.card_data if view != null and is_instance_valid(view) and not battle_controller.is_armed_for_devour_only() else null
	if card != null and battle_controller.marking_status(card) == null:
		card = null
	_armed_marking = card
	var mouse: Vector2 = get_viewport().get_mouse_position()
	# A card or button under the cursor wins over any intent's line.
	var over_ui: bool = get_viewport().gui_get_hovered_control() != null
	for enemy: FieldEnemy in _enemy_intents:
		var intent: BattleIntent = _enemy_intents[enemy]
		if not is_instance_valid(intent):
			continue
		var hovered_intent: bool = not over_ui and intent.is_visible_in_tree() and intent.get_pair_global_rect().has_point(mouse)
		if card == null:
			# Nothing armed: the hovered intent says what it does.
			intent.set_armed(BattleIntent.ARMED_NONE)
			intent.set_refusal(_intent_hover_text(enemy) if hovered_intent else "")
			continue
		var refusal: EnemyTurn.MarkRefusal = battle_controller.mark_refusal_for(card, enemy)
		if refusal == EnemyTurn.MarkRefusal.NONE:
			intent.set_armed(BattleIntent.ARMED_VALID)
			continue
		intent.set_armed(BattleIntent.ARMED_REFUSED)
		intent.set_refusal(_refusal_text(refusal, card, enemy) if hovered_intent else "")

# One line on what `enemy`'s queued intent does, with its numbers - the
# ones it will land, Brace and Garnish taken off (intent_hover_lines,
# BattleController.intent_facts()). "" for none.
func _intent_hover_text(enemy: FieldEnemy) -> String:
	var facts: Dictionary = battle_controller.intent_facts(enemy)
	if facts.is_empty():
		return ""
	var lines: Dictionary = intent_hover_lines
	var name: String = str(facts["name"])
	var preview: Dictionary = facts["preview"]
	var intent: EnemyIntent = facts["intent"]
	if bool(preview.get("pain_turn", false)):
		return str(lines.get(&"cancelled", "%s")) % name
	if bool(preview.get("denied", false)):
		return str(lines.get(&"denied", "%s")) % name
	if bool(preview.get("delayed", false)):
		return str(lines.get(&"delayed", "%s")) % name
	if bool(preview.get("interrupted", false)):
		return str(lines.get(&"broken", "%s")) % name
	var holds: String = ""
	var held: Array = facts["holds"]
	if held.size() == 2:
		holds = str(lines.get(&"holds", "")) % [held[0], held[1]]
	match int(preview.get("type", -1)):
		EnemyIntent.IntentType.ATTACK:
			if intent.lands_as_strike_back:
				return (str(lines.get(&"strike_back", "%s %d")) % [name, int(preview.get("per_hit", 0))]) + holds
			var line: String = str(lines.get(&"attack", "%s %s")) % [name, _attack_phrase(preview)]
			if facts.has("marks"):
				line = _marked_line(name, preview, facts)
			if intent.applies_to_player != null and intent.applied_amount > 0:
				line += str(lines.get(&"applies", "")) % [intent.applies_to_player.display_name, intent.applied_amount]
			if preview.has("threshold") and int(preview.get("threshold_left", 0)) > 0:
				line += str(lines.get(&"threshold", "")) % int(preview["threshold_left"])
			return line + holds
		EnemyIntent.IntentType.DEFEND:
			var times: int = maxi(int(preview.get("repeats", 1)), 1)
			if times > 1:
				return str(lines.get(&"defend_twice", "%s %d")) % [name, int(preview.get("per_hit", 0)) / times]
			return str(lines.get(&"defend", "%s %d")) % [name, int(preview.get("per_hit", 0))]
		EnemyIntent.IntentType.HEAL_ALLY:
			return str(lines.get(&"heal", "%s %d")) % [name, int(preview.get("per_hit", 0))]
		EnemyIntent.IntentType.SIGNAL:
			var answers: Array = facts["answers"]
			if answers.is_empty():
				return str(lines.get(&"signal_none", "%s")) % name
			var verb: String = str(lines.get(&"signal_wakes" if int(facts["waking"]) > 0 else &"signal_calls", ""))
			var total: int = 0
			var parts: PackedStringArray = PackedStringArray()
			var names: Array[String] = []
			var alike: bool = true
			for answer: Array in answers:
				total += int(answer[1])
				parts.append("%s %d" % [answer[0], int(answer[1])])
				if not names.has(str(answer[2])):
					names.append(str(answer[2]))
				if str(answer[0]) != str(answers[0][0]) or int(answer[1]) != int(answers[0][1]):
					alike = false
			# Who it calls, by their names: "the Nettles" (living, the total
			# theirs), "the Nettle" for one left.
			var who: PackedStringArray = PackedStringArray()
			for mate_name in names:
				var count: int = 0
				for answer: Array in answers:
					if str(answer[2]) == mate_name:
						count += 1
				who.append("the " + (mate_name + "s" if count > 1 else mate_name))
			if alike:
				return str(lines.get(&"signal", "%s %s %s %s %d %d")) % [name, verb, " and ".join(who), answers[0][0], int(answers[0][1]), total]
			return str(lines.get(&"signal_mixed", "%s %s %s %s %d")) % [name, verb, " and ".join(who), ", ".join(parts), total]
		EnemyIntent.IntentType.DIG:
			var under: Array = facts["under"]
			if under.size() == 2:
				return str(lines.get(&"dig", "%s %s %d")) % [name, str(under[0]).to_lower() + "s", int(under[1])]
		EnemyIntent.IntentType.BURROW:
			return str(lines.get(&"burrow", "%s")) % name
		EnemyIntent.IntentType.WATCH:
			return str(lines.get(&"watch", "%s")) % name
	# What it brings until its next move (the Glower's Puff - Inflated, the
	# Adder's Coil - Coiled), or what it holds while queued (the Rebury).
	var brings: Array = facts["brings"]
	if brings.size() == 2:
		var status: StatusData = facts["brings_status"]
		var next: EnemyIntent = facts["next"]
		var until: String = str(lines.get(&"brings_any", "move"))
		if next != null:
			until = (str(lines.get(&"brings_next", "%s %d")) % [next.intent_name, next.value]) if next.value > 0 else next.intent_name
		var verb: String = status.gained_verb if status != null and not status.gained_verb.is_empty() else str(brings[0]).to_lower()
		return str(lines.get(&"brings", "%s %s %s %s %s")) % [name, verb, until, str(brings[0]).to_lower(), _status_effect_phrase(status, str(brings[1]))]
	return (str(lines.get(&"plain", "%s")) % name) + holds

# What a status a move brings does, for the hover's "While ..." clause,
# from its own data: a taunt and its incoming-damage modifier in plain
# words ("your single-target Attacks must hit it, for half damage"), else
# its description with its first letter lowered. Ends with a full stop.
func _status_effect_phrase(status: StatusData, described: String) -> String:
	var lines: Dictionary = intent_hover_lines
	var parts: PackedStringArray = PackedStringArray()
	if status != null and status.taunts:
		parts.append(str(lines.get(&"taunts", "")))
	if status != null and status.category == StatusData.Category.MODIFIER and status.modifier_target == StatusData.ModifierTarget.INCOMING_DAMAGE and status.modifier_operation == StatusData.ModifierOperation.MULTIPLY and status.default_magnitude != 0:
		var by: int = absi(status.default_magnitude)
		if status.default_magnitude == -50:
			parts.append(str(lines.get(&"half_damage", "")))
		elif status.default_magnitude < 0:
			parts.append(str(lines.get(&"less_damage", "%d")) % by)
		else:
			parts.append(str(lines.get(&"more_damage", "%d")) % by)
	if not parts.is_empty() and status != null and status.taunts:
		return ", ".join(parts) + "."
	var text: String = described.strip_edges()
	if text.is_empty():
		return ""
	text = text.substr(0, 1).to_lower() + text.substr(1)
	return text if text.ends_with(".") else text + "."

# An attack's numbers, as it will land: "6", "5 ×3", "11 over 3 hits", and
# "... twice" for an enemy acting twice (each action alike).
func _attack_phrase(preview: Dictionary) -> String:
	var lines: Dictionary = intent_hover_lines
	var times: int = maxi(int(preview.get("repeats", 1)), 1)
	var hits: int = maxi(int(preview.get("hits", 1)) / times, 1)
	var amounts: Array = preview.get("hit_amounts", [])
	var mine: Array = amounts.slice(0, hits)
	var phrase: String = str(int(preview.get("per_hit", 0)))
	if hits > 1:
		if not mine.is_empty() and mine.count(mine[0]) == mine.size():
			phrase = str(lines.get(&"hits", "%d x%d")) % [int(mine[0]), hits]
		else:
			var total: int = 0
			for amount: Variant in mine:
				total += int(amount)
			phrase = str(lines.get(&"total", "%d %d")) % [total, hits]
	if times > 1:
		phrase = str(lines.get(&"twice", "%s")) % phrase
	return phrase

# A marked attack's breakdown, from data: its numbers without the marks
# (BattleController.intent_facts() "unmarked_hits", as _attack_phrase()
# reads them), each mark by its name with what it takes - a modifier's
# percentage (-50 "halved"), a total reduction its magnitude "in all" -
# then every hit as it will land and, for more than one, their total.
func _marked_line(name: String, preview: Dictionary, facts: Dictionary) -> String:
	var lines: Dictionary = intent_hover_lines
	var unmarked: Array = facts.get("unmarked_hits", [])
	var before: Dictionary = {"hits": unmarked.size(), "repeats": preview.get("repeats", 1), "hit_amounts": unmarked, "per_hit": int(unmarked[0]) if not unmarked.is_empty() else 0}
	var parts: PackedStringArray = PackedStringArray()
	for active: Status in facts["marks"]:
		parts.append(_mark_phrase(active))
	var landing: Array = preview.get("hit_amounts", [])
	var each: PackedStringArray = PackedStringArray()
	var total: int = 0
	for amount: Variant in landing:
		each.append(str(int(amount)))
		total += int(amount)
	var lands: String = ", ".join(each)
	if landing.size() > 1:
		lands = str(lines.get(&"lands_hits", "%s %d")) % [lands, total]
	return str(lines.get(&"marked", "%s %s %s %s")) % [name, _attack_phrase(before), ", ".join(parts), lands]

# One mark on an intent, by what its data does to the attack.
func _mark_phrase(active: Status) -> String:
	var lines: Dictionary = intent_hover_lines
	var status: StatusData = active.data
	if status.reduces_attack_total:
		return str(lines.get(&"mark_less_in_all", "%s %d")) % [status.display_name, active.magnitude]
	if status.category == StatusData.Category.MODIFIER and status.modifier_operation == StatusData.ModifierOperation.MULTIPLY:
		if active.magnitude == -50:
			return str(lines.get(&"mark_halved", "%s")) % status.display_name
		if active.magnitude < 0:
			return str(lines.get(&"mark_less_percent", "%s %d")) % [status.display_name, -active.magnitude]
		return str(lines.get(&"mark_more_percent", "%s %d")) % [status.display_name, active.magnitude]
	return status.display_name

# What a refused intent says while an armed Brace or Garnish hovers it.
func _refusal_text(refusal: EnemyTurn.MarkRefusal, card: CardData, enemy: FieldEnemy) -> String:
	var name: String = battle_controller.queued_intent_name(enemy)
	match refusal:
		EnemyTurn.MarkRefusal.ONLY_BLOCK:
			return mark_refusal_only_block % name
		EnemyTurn.MarkRefusal.NOT_ATTACK:
			return mark_refusal_not_attack % name
		EnemyTurn.MarkRefusal.WONT_LAND:
			return mark_refusal_wont_land % name
		EnemyTurn.MarkRefusal.ALREADY:
			var status_data: StatusData = battle_controller.marking_status(card)
			return str(mark_refusal_already.get(status_data.intent_mark if status_data != null else &"", ""))
	return ""

# One plate per standing mound of each dug-in enemy whose row is up
# (FieldEnemy.is_dug_in()), its HP the mound's own; a broken or gone
# mound's plate goes, and every one of an enemy that has come up.
func _sync_mound_plates() -> void:
	if battle_controller == null:
		return
	var wanted: Dictionary = {}
	for enemy in battle_controller.enemies:
		if not is_instance_valid(enemy) or not enemy.is_dug_in():
			continue
		var guards: Array[Combatant] = battle_controller.mound_guards_of(enemy)
		for mound in guards.size():
			if guards[mound] == null:
				continue
			var key: String = _mound_key(enemy, mound)
			wanted[key] = true
			if not _mound_plates.has(key):
				var plate := (load(MOUND_PLATE_SCENE_PATH) as PackedScene).instantiate() as EnemyStatus
				add_child(plate)
				plate.set_mound(enemy, mound)
				plate.update_hp(guards[mound].hp, guards[mound].max_hp)
				_mound_plates[key] = plate
	for key: String in _mound_plates.keys():
		if not wanted.has(key):
			var plate: EnemyStatus = _mound_plates[key]
			if is_instance_valid(plate):
				plate.queue_free()
			_mound_plates.erase(key)

func _mound_key(enemy: FieldEnemy, mound: int) -> String:
	return "%d:%d" % [enemy.get_instance_id(), mound]

# A hit on a mound (BattleController.mound_damaged): its plate's HP (with
# the ghost), its number over the mound - sized by its share of the
# mound's HP, a break the top size - and the hit's reaction.
func _on_mound_damaged(enemy: FieldEnemy, mound: int, amount: int, hp: int, max_hp: int) -> void:
	if not is_instance_valid(enemy):
		return
	if _battle_feedback != null:
		_battle_feedback.on_mound_damaged(enemy, mound, amount, hp, max_hp)
	var key: String = _mound_key(enemy, mound)
	var plate: EnemyStatus = _mound_plates.get(key)
	var avoid: Array[Rect2] = []
	if plate != null and is_instance_valid(plate):
		plate.update_hp(hp, max_hp)
		avoid.append(plate.get_global_rect())
	var shared: BattleIntent = _enemy_intents.get(enemy)
	if shared != null and is_instance_valid(shared) and shared.is_visible_in_tree():
		avoid.append(shared.get_global_rect())
	var camera := get_viewport().get_camera_3d()
	var body: Rect2 = enemy.get_mound_screen_rect(camera, mound, 0.0) if camera != null else Rect2()
	if not body.has_area():
		return
	var size: float = _battle_feedback.number_multiplier(float(amount) / float(maxi(max_hp, 1)), hp <= 0) if _battle_feedback != null else 1.0
	_place_number(key, FloatingNumber.KIND_DAMAGE, amount, Vector2(body.get_center().x, body.position.y - number_over_body_px), size, avoid, enemy)

# No two readouts overlap: every enemy's HP/name plate and intent, and his
# HP bar (which never moves), as they would stand (their own placement,
# less the offset this gave them), pushed apart - sideways first, by
# whichever way they overlap least - until readout_gap_px lies between
# each pair. Each keeps the offset as its layout_offset, which its own
# placement adds every frame.
func _lay_out_readouts() -> void:
	var nodes: Array[Control] = []
	var rects: Array[Rect2] = []
	var movable: Array[bool] = []
	for display in _enemy_statuses.values() + _enemy_intents.values() + _mound_plates.values():
		var control := display as Control
		if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		var offset: Vector2 = control.get("layout_offset")
		var rect: Rect2 = control.get_global_rect()
		if not rect.has_area():
			continue
		nodes.append(control)
		rects.append(Rect2(rect.position - offset, rect.size))
		movable.append(true)
	if _field_hp_bar != null and _field_hp_bar.is_visible_in_tree():
		nodes.append(_field_hp_bar)
		rects.append(_field_hp_bar.get_global_rect())
		movable.append(false)
	var shifts: Array[Vector2] = []
	shifts.resize(nodes.size())
	shifts.fill(Vector2.ZERO)
	for _pass in 8:
		var moved: bool = false
		for i in nodes.size():
			for j in range(i + 1, nodes.size()):
				if not movable[i] and not movable[j]:
					continue
				var a: Rect2 = Rect2(rects[i].position + shifts[i], rects[i].size).grow(readout_gap_px * 0.5)
				var b: Rect2 = Rect2(rects[j].position + shifts[j], rects[j].size).grow(readout_gap_px * 0.5)
				if not a.intersects(b):
					continue
				var overlap: Rect2 = a.intersection(b)
				var push := Vector2.ZERO
				if overlap.size.x <= overlap.size.y * 2.0:
					push.x = overlap.size.x * (1.0 if a.get_center().x <= b.get_center().x else -1.0)
				else:
					push.y = overlap.size.y * (1.0 if a.get_center().y <= b.get_center().y else -1.0)
				if movable[i] and movable[j]:
					shifts[i] -= push * 0.5
					shifts[j] += push * 0.5
				elif movable[j]:
					shifts[j] += push
				else:
					shifts[i] -= push
				moved = true
		if not moved:
			break
	for i in nodes.size():
		if movable[i]:
			nodes[i].set("layout_offset", shifts[i].round())

# The plates outlive the fight (each FieldEnemy's own): what the layout
# moved them by goes with it.
func _exit_tree() -> void:
	for display in _enemy_statuses.values():
		if display != null and is_instance_valid(display):
			(display as Control).set("layout_offset", Vector2.ZERO)

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
			# The card's condition live as it plays: its own pitch and
			# lift (CardData.critical_sound_pitch / _volume_db), 1.0 and 0
			# by default.
			var live: bool = _condition_live_at_commit(card)
			_card_override_player.pitch_scale = card.critical_sound_pitch if live else 1.0
			_card_override_player.volume_db = card_override_volume_db + (card.critical_sound_volume_db if live else 0.0)
			_card_override_player.play()
			return
		push_warning("BattleOverlay: '%s' names a play sound that failed to load (%s); using the shared cue." % [card.card_name, card.play_sound_path])
	if _card_play_player != null and _card_play_player.stream != null:
		_card_play_player.volume_db = card_play_volume_db
		_card_play_player.play()

# Whether `card`'s condition is live as it is committed - the face's
# reading (CardBonus.state()) of the battle as it stands then: the card's
# Energy paid, nothing of it resolved, and itself not among the cards
# played before it (the commit has already counted it). Critical is read
# at the HP the card will have paid before its conditions, as the face
# reads it (CardBonus.upfront_hp_cost()): In the Red's own 8, the stance's
# price on an Attack, and the HP this play pays for Energy short
# (Collateral - BattleController.play_hp_cost, read before the commit
# spent the Energy).
func _condition_live_at_commit(card: CardData) -> bool:
	if battle_controller == null or battle_controller.player == null:
		return false
	var ctx: EffectContext = battle_controller.preview_context()
	ctx.cards_played_before_this = maxi(ctx.cards_played_before_this - 1, 0)
	var paid: EffectContext = ctx.for_card_preview(CardBonus.upfront_hp_cost(card, ctx.player.stance, battle_controller.play_hp_cost))
	return CardBonus.state(card, paid) == CardBonus.State.LIVE

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

# Devour's bite sound, as the card is bitten (HandContainer.devour_card()
# cuts the notch the same frame - the clack is at each take's start): a
# take other than the last one, on the SFX bus.
func _play_devour_take() -> void:
	if _devour_player == null:
		_devour_player = AudioStreamPlayer.new()
		_devour_player.bus = &"SFX"
		add_child(_devour_player)
		for path in DEVOUR_SFX_PATHS:
			var stream := load(path) as AudioStream
			if stream != null:
				_devour_takes.append(stream)
			else:
				push_warning("BattleOverlay: a Devour take failed to load (%s)." % path)
	if _devour_takes.is_empty():
		return
	var take: int = randi_range(0, _devour_takes.size() - 1)
	if _devour_takes.size() > 1 and take == _devour_last_take:
		take = (take + randi_range(1, _devour_takes.size() - 1)) % _devour_takes.size()
	_devour_last_take = take
	_devour_player.stream = _devour_takes[take]
	_devour_player.volume_db = devour_volume_db
	_devour_player.play()

# The Devour keyword's sound, as the eaten card's bite starts
# (BattleController._on_keyword_devoured()), on the SFX bus.
func _play_devour_keyword() -> void:
	if _devour_keyword_player == null:
		_devour_keyword_player = AudioStreamPlayer.new()
		_devour_keyword_player.bus = &"SFX"
		add_child(_devour_keyword_player)
		_devour_keyword_player.stream = load(DEVOUR_KEYWORD_SFX_PATH) as AudioStream
		if _devour_keyword_player.stream == null:
			push_warning("BattleOverlay: the Devour keyword's sound failed to load (%s)." % DEVOUR_KEYWORD_SFX_PATH)
	if _devour_keyword_player.stream == null:
		return
	_devour_keyword_player.volume_db = devour_keyword_volume_db
	_devour_keyword_player.play()

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
func _on_damage_dealt(_source: Variant, target: Variant, amount: int, kind: String) -> void:
	var number_kind: String = FloatingNumber.KIND_DAMAGE
	if not (target is FieldEnemy):
		number_kind = FloatingNumber.KIND_SELF if kind == "self" else FloatingNumber.KIND_HP_LOST
	_show_number(target, amount, number_kind)

# A number of `kind` (FloatingNumber's KIND_*) for `amount` on `target` -
# a FieldEnemy or "player" - shown over its body.
func _show_number(target: Variant, amount: int, kind: String) -> void:
	var delay: float = _battle_feedback.reaction_delay(target) if _battle_feedback != null else 0.0
	# Read in the hit's own frame, while its card is still the impact's.
	var sized: bool = kind == FloatingNumber.KIND_DAMAGE or kind == FloatingNumber.KIND_HP_LOST
	var size: float = _battle_feedback.number_scale(target, amount) if _battle_feedback != null and sized else 1.0
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if target is Object and not is_instance_valid(target):
			return
	# A multi-hit's numbers step on from each other while the last shows.
	var key: Variant = target if target is FieldEnemy else "player"
	# Clear of its own readouts: an enemy's intent and plate, his HP bar.
	var avoid: Array[Rect2] = []
	var readouts: Array = [_enemy_intents.get(target), _enemy_statuses.get(target)] if target is FieldEnemy else [_field_hp_bar]
	for display in readouts:
		var control := display as Control
		if control != null and is_instance_valid(control) and control.is_visible_in_tree():
			avoid.append(control.get_global_rect())
	_place_number(key, kind, amount, _screen_pos_for_damage_target(target), size, avoid, target as FieldEnemy if target is FieldEnemy else null)

# A number of `kind` for `amount` at `screen_pos` (its bottom centre),
# stepping on from `key`'s numbers still showing (a multi-hit's stack,
# sharing its first's jitter), clear of `avoid`.
func _place_number(key: Variant, kind: String, amount: int, screen_pos: Vector2, size: float, avoid: Array[Rect2], owner: FieldEnemy = null) -> void:
	var shown: int = int(_number_counts.get(key, 0))
	var stack: Vector2 = number_stack_step * float(shown)
	_number_counts[key] = shown + 1
	get_tree().create_timer(_number_seconds()).timeout.connect(func() -> void:
		_number_counts[key] = maxi(int(_number_counts.get(key, 1)) - 1, 0))
	var jitter: float = NAN if shown == 0 else float(_stack_jitter.get(key, NAN))
	var number: FloatingNumber = _spawn_floating_number(kind, amount, screen_pos, size, avoid, stack, jitter)
	if shown == 0:
		_stack_jitter[key] = number.jitter.x
	# Over an enemy: its intent dims while this shows.
	if owner != null:
		var over: Array = _numbers_over.get(owner, [])
		over.append(number)
		_numbers_over[owner] = over

# Where `target`'s number sits - the bottom centre it is placed by: at
# an enemy's mid-body (number_body_fraction), over the Wanderer's head
# (wanderer_number_over_head_px).
func _screen_pos_for_damage_target(target: Variant) -> Vector2:
	if target is FieldEnemy:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var body: Rect2 = (target as FieldEnemy).get_screen_rect(camera, 0.0)
			if body.has_area():
				return Vector2(body.get_center().x, body.position.y + body.size.y * clampf(number_body_fraction, 0.0, 1.0))
			return camera.unproject_position((target as FieldEnemy).global_position + Vector3.UP * enemy_head_height)
	# "player": over the Wanderer's body.
	if _wanderer != null and is_instance_valid(_wanderer):
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var head: Vector2 = camera.unproject_position(_wanderer.global_position + Vector3.UP * _wanderer.get_head_height())
			return head - Vector2(0.0, wanderer_number_over_head_px)
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
# at the fight's end - save a basic attack, which goes in as the weapon
# plays it (BattleController.fight_card()), as every one in the fight
# did. Logged, so a run that used it can be left out of tuning.
func _on_debug_add_card_pressed() -> void:
	if battle_controller == null or battle_controller.deck == null or _debug_card_picker.selected < 0:
		return
	var card := _debug_card_picker.get_item_metadata(_debug_card_picker.selected) as CardData
	if card == null:
		return
	battle_controller.deck.add(battle_controller.fight_card(RunState.add_card(card)))
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
	# No Dig spray outlives the fight.
	if battle_controller != null:
		for enemy in battle_controller.enemies:
			if is_instance_valid(enemy):
				enemy.set_dig_spray(false)
	_field_hp_bar.hide_toll()
	# Grace is per fight (it lives on the Combatant, which this battle's
	# end discards) - the segment goes with it whatever the outcome.
	_field_hp_bar.hide_grace()
	# Stances and statuses are per fight, like Grace - the row goes with
	# them whatever the outcome.
	_field_hp_bar.clear_standing_row()
	# The HP bar's Critical line goes back with exit_battle(); the keyword
	# tooltip's here.
	KeywordTable.fight_critical_fraction = -1.0
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

# How long a killing hit of `amount` on `enemy` takes to show in full, in
# real seconds from its frame (BattleController.kill_presentation_time):
# its reaction and play effect (BattleFeedback.kill_presentation_time()),
# or its damage number's pop and hold, if that ends later - its fade plays
# over the death.
func _kill_presentation_time(enemy: FieldEnemy, amount: int) -> float:
	_read_number_times()
	if _battle_feedback == null:
		return _number_legible
	var number_end: float = _battle_feedback.reaction_delay(enemy) + _number_legible
	return maxf(_battle_feedback.kill_presentation_time(enemy, amount), number_end)

# A number's whole life (FloatingNumber.life_seconds()) - how long it
# counts toward its target's stack.
func _number_seconds() -> float:
	_read_number_times()
	return _number_life

# Read once off the scene.
func _read_number_times() -> void:
	if _number_life >= 0.0:
		return
	var number := (load(FLOATING_NUMBER_SCENE_PATH) as PackedScene).instantiate() as FloatingNumber
	_number_life = number.life_seconds() if number != null else 0.0
	_number_legible = number.legible_seconds() if number != null else 0.0
	if number != null:
		number.free()

# `screen_pos`: the number's bottom centre. `avoid`: rects the number
# keeps number_clearance_px off the whole way it rises (its own readouts) -
# moved beside them, the side with room on screen, when its path would
# cross one; then `stack` on from there (a multi-hit's step), so the
# numbers of one target never land on one spot. `jitter`: the sideways
# offset to land at - NAN draws one (FloatingNumber.jitter_px).
func _spawn_floating_number(kind: String, value: int, screen_pos: Vector2, size_multiplier: float = 1.0, avoid: Array[Rect2] = [], stack: Vector2 = Vector2.ZERO, jitter: float = NAN) -> FloatingNumber:
	var number := (load(FLOATING_NUMBER_SCENE_PATH) as PackedScene).instantiate() as FloatingNumber
	add_child(number)
	var size: Vector2 = number.measure(kind, value, size_multiplier)
	var at: Vector2 = screen_pos - Vector2(size.x / 2.0, size.y)
	# Its whole path - from where it starts, a multi-hit's step included, up
	# through its rise - clear of `avoid`: one it would cross pushes it down
	# below that readout, never beside it (where an intent's own numeral
	# would read as its neighbour).
	var path := Rect2(Vector2(at.x + stack.x, at.y + stack.y - number.rise_px), Vector2(size.x, size.y + number.rise_px)).grow(number_clearance_px)
	var blocked := Rect2()
	for rect in avoid:
		if path.intersects(rect):
			blocked = rect if not blocked.has_area() else blocked.merge(rect)
	if blocked.has_area():
		at.y = blocked.end.y + number_clearance_px * 2.0 + number.rise_px - stack.y
	# Its whole rise on screen.
	var start: Vector2 = at + stack
	start.y = maxf(start.y, number.rise_px + number_clearance_px)
	number.show_value(kind, value, start, size_multiplier, jitter)
	return number

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
	if _devour_button != null:
		_devour_button.refresh_style()
	end_turn_button.refresh_style()
	if _choice_done != null:
		_choice_done.refresh_style()
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
