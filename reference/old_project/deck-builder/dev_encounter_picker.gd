extends Node2D
class_name DevEncounterPicker
# Dev-only screen (see title_screen.gd's own "Dev: encounter picker"
# button) for loading directly into a specific battle without playing
# through the field first - replaces the old battle_number-keyed pin in
# battle.gd's _resolve_enemies_data() (see that function's own doc for
# why it was removed), which only ever reached 3 fixed fights, and only
# by chaining battles from the very start. This reaches ANY authored
# encounter or ANY ad-hoc 1-3 enemy combination, immediately, every time.
#
# Routes through RoomState.pending_encounter_enemies (see _start_battle()
# below) - the EXACT SAME seam field_blob.gd already uses for the field's
# own encounter preview. No parallel spawn path: battle.gd's
# _resolve_enemies_data() can't tell whether this screen or a real field
# encounter set that array, and doesn't need to.
#
# DEV AFFORDANCE - matches this project's ONLY existing convention for
# dev-only tools exactly (see battle.tscn's DevDamageButton/DevStatus
# Button/etc. and title_screen.tscn's own DevBattleChainButton): a
# plainly-labeled, always-visible button/screen. There is no release-
# build gating mechanism anywhere in this project (no OS.is_debug_build()
# check, no export feature tags - export_presets.cfg doesn't even exist
# yet) and this screen deliberately doesn't add one; that's a separate
# task, not something to bolt on here as a side effect.
#
# No picker state persists across launches (deliberate) - every field
# here resets to its own default the moment this scene loads, same as
# every other screen in the game today.

const ENEMY_ROSTER_MAX := 3

@onready var back_button: Button = $UI/Margin/Root/HeaderRow/BackButton
@onready var class_wanderer_button: Button = $UI/Margin/Root/ClassRow/ClassWandererButton
@onready var class_samurai_button: Button = $UI/Margin/Root/ClassRow/ClassSamuraiButton
@onready var mode_authored_button: Button = $UI/Margin/Root/ModeRow/ModeAuthoredButton
@onready var mode_adhoc_button: Button = $UI/Margin/Root/ModeRow/ModeAdhocButton
@onready var authored_panel: VBoxContainer = $UI/Margin/Root/AuthoredPanel
@onready var authored_list: VBoxContainer = $UI/Margin/Root/AuthoredPanel/AuthoredScroll/AuthoredList
@onready var adhoc_panel: HBoxContainer = $UI/Margin/Root/AdhocPanel
@onready var adhoc_enemy_list: VBoxContainer = $UI/Margin/Root/AdhocPanel/AdhocEnemyScroll/AdhocEnemyList
@onready var roster_label: Label = $UI/Margin/Root/AdhocPanel/AdhocSidebar/RosterLabel
@onready var clear_button: Button = $UI/Margin/Root/AdhocPanel/AdhocSidebar/ClearButton
@onready var start_button: Button = $UI/Margin/Root/AdhocPanel/AdhocSidebar/StartButton

var _selected_class: CharacterData = RunState.WANDERER
var _adhoc_roster: Array[EnemyData] = []

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	class_wanderer_button.pressed.connect(_on_class_wanderer_pressed)
	class_samurai_button.pressed.connect(_on_class_samurai_pressed)
	mode_authored_button.pressed.connect(_show_authored_mode)
	mode_adhoc_button.pressed.connect(_show_adhoc_mode)
	clear_button.pressed.connect(_on_clear_roster_pressed)
	start_button.pressed.connect(_on_adhoc_start_pressed)

	_build_authored_list()
	_build_adhoc_enemy_list()
	_refresh_roster_label()
	_show_authored_mode()

# --- Class toggle ---
#
# Two plain toggle buttons rather than an OptionButton - only two classes
# exist (see run_state.gd's WANDERER/SAMURAI consts), and this reads at a
# glance which is picked without opening a dropdown, for a screen used
# over and over during iteration. Does NOT affect the starting deck (see
# ClassNoteLabel in dev_encounter_picker.tscn) - run_state.gd's
# STARTING_DECK is universal regardless of class; this only changes which
# folder reward_screen.gd draws from later, via RunState.current_class.
# Samurai's pool is empty for now, so picking it means every reward roll
# comes up with nothing until cards get built.
func _on_class_wanderer_pressed() -> void:
	_selected_class = RunState.WANDERER
	class_wanderer_button.button_pressed = true
	class_samurai_button.button_pressed = false

func _on_class_samurai_pressed() -> void:
	_selected_class = RunState.SAMURAI
	class_wanderer_button.button_pressed = false
	class_samurai_button.button_pressed = true

# --- Mode switching ---
func _show_authored_mode() -> void:
	mode_authored_button.button_pressed = true
	mode_adhoc_button.button_pressed = false
	authored_panel.visible = true
	adhoc_panel.visible = false

func _show_adhoc_mode() -> void:
	mode_authored_button.button_pressed = false
	mode_adhoc_button.button_pressed = true
	authored_panel.visible = false
	adhoc_panel.visible = true

# --- Mode 1: Authored encounters ---
#
# Separate EncounterPool.list_all() calls per folder, not one merged
# scan - see encounter_pool.gd's own doc on why the folder itself is the
# only signal for which entries are elite (EncounterData has no is_elite
# field of its own). Selecting a row starts the battle immediately - no
# separate "confirm" step for Mode 1, unlike Mode 2's roster-then-Start.
#
# SUNKEN_WORKS_ENCOUNTER_FOLDER (discovered 2026-08-27, this pass) -
# mushroom_patch.tres actually lives in a biome subfolder (resources/
# encounters/sunken_works/), not the top level EncounterPool.
# ENCOUNTER_FOLDER scans. DirAccess.get_files() doesn't recurse (same
# limitation ELITE_ENCOUNTER_FOLDER already works around with its own
# explicit folder), so room_state.gd's own ordinary encounter_chance roll
# (EncounterPool.pick_random(), no folder arg) can ALREADY never reach
# this encounter either - a pre-existing gap in normal run progression,
# not something this pass introduces or is scoped to fix (see this
# feature's own OUT OF SCOPE note). Scanning this folder HERE, only in
# this dev tool, makes Mushroom Patch reachable for testing without
# touching room_state.gd's real roll at all. Only one biome exists today
# (see run_state.gd's SUNKEN_WORKS) - revisit this as a real per-biome
# loop if a second one ever ships.
const SUNKEN_WORKS_ENCOUNTER_FOLDER := "res://resources/encounters/sunken_works/"

func _build_authored_list() -> void:
	for child in authored_list.get_children():
		child.queue_free()
	for encounter: EncounterData in EncounterPool.list_all():
		_add_authored_row(encounter, false)
	for encounter: EncounterData in EncounterPool.list_all(SUNKEN_WORKS_ENCOUNTER_FOLDER):
		_add_authored_row(encounter, false)
	for encounter: EncounterData in EncounterPool.list_all(EncounterPool.ELITE_ENCOUNTER_FOLDER):
		_add_authored_row(encounter, true)

func _add_authored_row(encounter: EncounterData, is_elite: bool) -> void:
	var enemy_names: Array[String] = []
	for enemy: EnemyData in encounter.enemies:
		enemy_names.append(enemy.enemy_name)
	var label := "%s  -  %s" % [encounter.encounter_name, ", ".join(enemy_names)]
	if is_elite:
		label = "[ELITE] " + label
	var button := Button.new()
	button.text = label
	button.pressed.connect(_start_battle.bind(encounter.enemies))
	authored_list.add_child(button)

# --- Mode 2: Ad-hoc roster ---
#
# include_opening=true, include_encounter_only=true, and include_bosses=
# true (see enemy_pool.gd's own doc on all three) - a dev iterating on
# Tideworn/Unrelieved/Mushroom, or on Leviathan specifically, has a real
# reason to reach them directly here, unlike an ordinary random
# encounter or the real run graph's own boss room. Thicket Stalker
# (resources/enemies/retired/) never appears - EnemyPool.list_all()
# never scans that folder at all, cut content, same as everywhere else.
#
# Every button in adhoc_enemy_list ADDS to _adhoc_roster on click (not a
# select-then-confirm row) - clicking the same enemy three times is how
# "the same enemy more than once" actually happens, no separate
# stepper/count control needed.
func _build_adhoc_enemy_list() -> void:
	for child in adhoc_enemy_list.get_children():
		child.queue_free()
	for enemy: EnemyData in EnemyPool.list_all(true, true, true):
		var button := Button.new()
		button.text = enemy.enemy_name
		button.pressed.connect(_on_adhoc_enemy_picked.bind(enemy))
		adhoc_enemy_list.add_child(button)

func _on_adhoc_enemy_picked(enemy: EnemyData) -> void:
	if _adhoc_roster.size() >= ENEMY_ROSTER_MAX:
		return
	_adhoc_roster.append(enemy)
	_refresh_roster_label()

func _on_clear_roster_pressed() -> void:
	_adhoc_roster.clear()
	_refresh_roster_label()

func _refresh_roster_label() -> void:
	if _adhoc_roster.is_empty():
		roster_label.text = "Roster: (empty)"
	else:
		var names: Array[String] = []
		for enemy: EnemyData in _adhoc_roster:
			names.append(enemy.enemy_name)
		roster_label.text = "Roster (%d/%d): %s" % [_adhoc_roster.size(), ENEMY_ROSTER_MAX, ", ".join(names)]
	start_button.disabled = _adhoc_roster.is_empty()

func _on_adhoc_start_pressed() -> void:
	_start_battle(_adhoc_roster.duplicate())

# --- Shared entry point ---
#
# Same reset/transition sequence title_screen.gd's own Dev Battle Chain
# uses (RunState.reset(), RoomState.reset_room(), current_room_type =
# COMBAT, SceneTransition.go_to()) - the only addition is setting
# pending_encounter_enemies (see this file's own header on why that's
# the one seam this routes through) and overriding current_class AFTER
# reset() (reset() itself hardcodes WANDERER first - see run_state.gd -
# so setting this any earlier would just get overwritten). Picking
# Samurai here starts a run with an empty reward pool (its card folder
# has nothing in it yet).
#
# current_room_type stays COMBAT even for an elite-sourced pick - same
# as Dev Battle Chain's own former battle-3 Wardling pin never set ELITE
# either. This only affects reward_screen.gd's reward-pool flavor, out
# of scope for this pass.
func _start_battle(enemies: Array[EnemyData]) -> void:
	RunState.reset()
	RunState.current_class = _selected_class
	RoomState.reset_room()
	RoomState.current_room_type = RoomType.Kind.COMBAT
	RoomState.pending_encounter_enemies = enemies
	SceneTransition.go_to("res://battle.tscn")

func _on_back_pressed() -> void:
	SceneTransition.go_to("res://title_screen.tscn")
