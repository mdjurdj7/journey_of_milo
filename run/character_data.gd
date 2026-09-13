extends Resource
class_name CharacterData

# One character's own starting numbers - deliberately minimal (name, max
# HP, starting deck composition, and the Rally recovery percent Combatant.
# rally_recovery_percent was already carrying as a placeholder - see that
# field's own doc). No class-select UI exists yet; RunState.new_run() is
# just handed one of these directly by whatever calls it (region_field.gd,
# for now - see its own doc).

@export var character_name: String = ""
@export var max_hp: int = 70

# CardData -> copy count: the run's starting Belongings. Keys are real
# CardData resource references (wired up in the Inspector), not path
# strings, so RunState._build_starting_deck() needs no load()/preload()
# at all to resolve them.
@export var starting_deck_counts: Dictionary = {}

@export var rally_recovery_percent: int = 50
