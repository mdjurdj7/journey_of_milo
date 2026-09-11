extends Node2D
# Boots the game. This is the only place "start a brand new run from
# nothing" happens - RunState.reset() (which builds a fresh run graph -
# see run_state.gd) followed by RoomState.load_room() with that graph's
# start node's type, to actually enter the run. Defeat's button (see
# battle.gd) only navigates back here; it doesn't reset anything itself,
# so this stays the single source of truth for what "a fresh run" means.
#
# The title text itself lives entirely in TitleLabel's `text` property in
# title_screen.tscn, not here - swapping "WORKING TITLE" for a real name
# later is a one-line edit to that property (in the editor or the .tscn
# file), no code to hunt through.
#
# Restyle (2026-08-27) - two voices, same convention weapon_pickup_
# window.tscn already established: Spectral for the title (world voice),
# the project's default sans for the menu (system voice, untouched -
# same "no font override means the project default" shape every other
# system-voice label there already follows). Buttons are flat=true with
# StyleBoxEmpty/StyleBoxFlat-underline overrides copied from that same
# window's Take it/Leave it - this game has no filled buttons anywhere,
# and this scene isn't an exception. Duplicated here, not shared, per
# this rework's own scope note (title_screen.tscn/.gd only) - this
# scene owns its own copies of those StyleBox resources.

const TITLE_GLYPH_SPACING := -2

const DEV_TRINKET := preload("res://resources/trinkets/amnesty.tres")
# Debug-only grant (2026-08-28, trinket pass) - no pickup/loot/reward/
# deck-viewer UI exists for trinkets yet (see trinket_data.gd's own
# scope note), so Dev Battle Chain (below) granting this directly is the
# only way to reach TOLL_THRESHOLD_FREE_CARD in a real fight today. Not
# wired into Begin Run - a real run should never start with an
# ungranted trinket already equipped.

@onready var title_label: Label = $UI/ContentColumn/TitleLabel
@onready var begin_run_button: Button = $UI/ContentColumn/MenuList/BeginRunButton
@onready var card_glossary_button: Button = $UI/ContentColumn/MenuList/CardGlossaryButton
@onready var dev_battle_chain_button: Button = $UI/ContentColumn/MenuList/DevBattleChainButton
@onready var dev_encounter_picker_button: Button = $UI/ContentColumn/MenuList/DevEncounterPickerButton
@onready var quit_button: Button = $UI/ContentColumn/MenuList/QuitButton

# Godot Labels have no letter-spacing property of their own - a
# FontVariation wrapping the label's own base font, with set_spacing(),
# is what actually produces the tracked look (same technique weapon_
# pickup_window.gd's own _setup_letter_spacing() uses, negative here
# instead of positive: Spectral is a text face and runs loose at 90px,
# so this tightens it rather than tracking it further out).
var _title_font: FontVariation

func _ready() -> void:
	_setup_title_letter_spacing()
	begin_run_button.pressed.connect(_on_begin_run_pressed)
	card_glossary_button.pressed.connect(_on_card_glossary_pressed)
	dev_battle_chain_button.pressed.connect(_on_dev_battle_chain_pressed)
	dev_encounter_picker_button.pressed.connect(_on_dev_encounter_picker_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	MusicManager.play_music("title_theme")

func _setup_title_letter_spacing() -> void:
	_title_font = FontVariation.new()
	_title_font.base_font = title_label.get_theme_font("font")
	_title_font.set_spacing(TextServer.SPACING_GLYPH, TITLE_GLYPH_SPACING)
	title_label.add_theme_font_override("font", _title_font)

# The real run: field rooms, encounters fought within them, deepening
# room_number - see DESIGN.md's Run Structure & Navigation for why.
func _on_begin_run_pressed() -> void:
	AudioManager.play_sfx("game_start")
	RunState.reset()
	RunLogger.log_opening_room(RunState.current_node)
	RoomState.load_room(RunState.current_node.room_type)

# Browse any character's full card pool for reference/brainstorming - see
# card_glossary.gd's own header. A real main-menu entry, not a dev-only
# affordance (unlike Dev Battle Chain/Dev Encounter Picker below): it
# doesn't touch RunState at all, just opens the glossary screen directly.
func _on_card_glossary_pressed() -> void:
	SceneTransition.go_to("res://card_glossary.tscn")

# Skips straight to a battle, chaining directly into the next one on
# Continue instead of through a field room - kept as a dev/testing
# shortcut for battle-only iteration, not part of the real run anymore.
func _on_dev_battle_chain_pressed() -> void:
	RunState.reset()
	RunState.equipped_trinket = DEV_TRINKET # Debug-only grant - see DEV_TRINKET's own doc.
	# This path never calls RoomState.load_room() (there's no field room
	# to generate), so RoomState.reset_room() - which clears pending_
	# enemy_data/pending_encounter_enemies - never runs either. Without
	# this, whatever those were left as by an EARLIER "Begin Run" field
	# encounter this same session would leak in here and permanently
	# override battle.gd's _resolve_enemies_data() battle_number pinning
	# (battle 1 = Beachwrack, battle 2 = Outbound, battle 3 = Wardling -
	# see its own comment) for every fight in the chain, since that check
	# happens
	# BEFORE battle_number is ever consulted. current_room_type is reset
	# to COMBAT for the same reason - a leftover BOSS/ELITE from that
	# same earlier session would otherwise still scale/relabel whatever
	# enemy battle 1 rolls.
	RoomState.reset_room()
	RoomState.current_room_type = RoomType.Kind.COMBAT
	SceneTransition.go_to("res://battle.tscn")

# Opens the dev encounter picker (see dev_encounter_picker.gd's own
# header) - a real scene, not a mode of this one, so it can also be
# opened directly in the editor without going through the title screen
# at all. Unlike Dev Battle Chain above, it doesn't call RunState.reset()
# here - the picker screen itself does that once the dev actually starts
# a fight, same reasoning battle.tscn never resets on load either.
func _on_dev_encounter_picker_pressed() -> void:
	SceneTransition.go_to("res://dev_encounter_picker.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
