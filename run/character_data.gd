extends Resource
class_name CharacterData

# One character's own starting numbers - name, max HP, starting deck
# composition, and the class passive. No class-select UI exists yet;
# RunState.new_run() is just handed one of these directly by whatever
# calls it (region_field.gd, for now - see its own doc).

@export var character_name: String = ""
@export var max_hp: int = 70

# CardData -> copy count: the run's starting Belongings. Keys are real
# CardData resource references (wired up in the Inspector), not path
# strings, so RunState._build_starting_deck() needs no load()/preload()
# at all to resolve them.
@export var starting_deck_counts: Dictionary = {}

# How much Grace one enemy turn can open, when several hits land in it.
#   LARGEST_HIT - the biggest single unblocked hit of that turn.
#   SUM         - every unblocked hit added together.
enum GraceCapMode { LARGEST_HIT, SUM }

# --- Grace, the Wanderer's passive ---
#
# HP an enemy takes off you is not gone yet: it becomes Grace, and damage
# you deal on your next turn takes it back 1:1. What you don't reclaim by
# the end of that turn is lost for good.
#
# Only unblocked ENEMY damage opens it - block and absorb eat their share
# first, and self-damage (Bite Down, a status tick) never opens any,
# because that is a price you chose. Reclaimed HP generates no Toll: Toll
# only ever comes from self-inflicted loss, so there is nothing to undo.
#
# Replaces the Rally passive, which was the same idea at 50% of the
# largest hit per CARD rather than 1:1 per turn - see DESIGN.md.
@export var has_grace: bool = false
@export var grace_cap_mode: GraceCapMode = GraceCapMode.LARGEST_HIT
# How many of the player's turns the window stays open for. 1 is "your
# next turn, then it's gone".
@export var grace_window_turns: int = 1
