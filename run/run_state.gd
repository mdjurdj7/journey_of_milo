extends Node

# Registered as the "RunState" autoload (see project.godot's [autoload]
# section) - Godot creates exactly one instance before any scene loads and
# keeps it alive for the whole game session, reachable from anywhere as
# just `RunState`. No class_name here, deliberately: RunState is one
# specific always-there object, not a type anything else should ever make
# a second instance of, and the autoload name is already its global
# identifier.
#
# Holds only what survives past a single battle: the player's HP, the
# run's deck (its Belongings - see deck_changed's own doc on what leaves
# it and when), which character this run is playing, and where in the
# run's structure the player currently is. Everything rebuilt fresh every
# fight (energy, block, statuses, hand/draw/discard/exhaust piles) stays
# local to Combatant/Deck inside BattleController - see its own setup().

signal player_hp_changed(current: int, max_hp: int)
signal deck_changed()
# Emits the NEW TOTAL, not the delta - same shape player_hp_changed uses,
# and what a readout actually wants to draw.
signal gold_changed(amount: int)

var player_hp: int = 0
var player_max_hp: int = 0

# The run's Belongings - every CardData instance this run currently owns.
# BattleController.setup() wraps a fresh per-fight Deck around this same
# array (Deck.new(RunState.deck)) rather than copying it, so a card
# played, discarded, or SPENT-exhausted this fight is still this exact
# same instance; only a CONSUMED removal (see region_field.gd's own
# _apply_consumed_removals(), called at battle end) ever calls remove_
# card() to take one out for good. SPENT cards never touch RunState at
# all - they just aren't reachable again until Deck.new() rebuilds next
# fight's draw pile from whatever's still here.
var deck: Array[CardData] = []

# Coin off the dead. Mutated only through add_gold()/spend_gold() below,
# the same way HP and the deck are - nothing writes this field directly,
# so nothing can change it without the readouts hearing.
var gold: int = 0

var character: CharacterData = null

var current_region_index: int = 0
var current_floor_index: int = 0

# The zone intro (ZoneIntro, played by RegionField) is owed exactly once,
# by the first floor of a NEW run: new_run() raises this and RegionField
# consumes it (reads and clears) in its _ready(). A floor change
# (reload_current_scene()) and the RunOver restart (change_scene back to
# the field) never call new_run(), so neither raises it - the intro is a
# run's first frame, not a floor's.
var run_opening_pending: bool = false

# Raised by the boot scene (TitleScreen) alone, consumed by RegionField's
# _ready(): the field holds the title (ZoneIntro.hold_title() - the intro's
# frame zero with the TitleMenu over it) instead of playing the intro
# outright. F6 on the field and a RunOver restart never raise it.
var title_pending: bool = false

# The run's one generator. Everything that rolls something a player could
# call luck draws from HERE rather than from the global randi(), so a run
# is one sequence and can be replayed from its seed: the Keeper's card
# (Keeper._pick_card()) and a fight's reward spread (RewardSpread) both
# use it today. Seeded in new_run(); `seed` is kept so a run can say
# which one it was, and so a future "replay this seed" has something to
# set. Deliberately NOT used for anything cosmetic - a bird's flight or a
# wave's phase must not shift the card you are about to be offered.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var run_seed: int = 0

# Starts a brand new run: seeds HP and the starting Belongings from
# `starting_character`'s own values, resets run-graph position. The only
# intended caller today is region_field.gd's _ready() (called once at
# game start) - see its own doc for why a proper run-start flow (a
# character-select screen, etc.) isn't wired up yet.
func new_run(starting_character: CharacterData) -> void:
	character = starting_character
	# Fresh seed per run, recorded rather than thrown away. randi() is
	# fine as the SOURCE of a seed - it's the one roll that doesn't need
	# to be reproducible, since it's what makes the rest of them so.
	run_seed = randi()
	rng.seed = run_seed
	gold = 0
	player_max_hp = starting_character.max_hp
	player_hp = player_max_hp
	deck = _build_starting_deck(starting_character)
	current_region_index = 0
	current_floor_index = 0
	# Field findings (a Hull's one-time world line, a Bird's one-time
	# flight, the Keeper's one-time offer, a belongings cache's one
	# choice) are remembered per run in their own static sets - see
	# Hull._findings_shown / Bird._flown / Keeper._offers_made /
	# BelongingsCache._spent - so a new run starts with none of them spent.
	Hull.reset_findings()
	Bird.reset_flights()
	Keeper.reset_offers()
	BelongingsCache.reset_spent()
	run_opening_pending = true
	player_hp_changed.emit(player_hp, player_max_hp)
	deck_changed.emit()
	gold_changed.emit(gold)

func _build_starting_deck(starting_character: CharacterData) -> Array[CardData]:
	var cards: Array[CardData] = []
	for card_data: CardData in starting_character.starting_deck_counts:
		var copies: int = int(starting_character.starting_deck_counts[card_data])
		for i in copies:
			cards.append(card_data.duplicate() as CardData)
	return cards

# Every player_hp-changing call site (BattleController's combat damage and
# status-tick bypass ticks included - see its own setup()/_report_damage()/
# _start_player_turn()) should go through this, heal(), or set_max_hp()
# rather than writing `player_hp` directly, or player_hp_changed silently
# stops being accurate.
#
# Floors at 0, not 1 - combat is the only HP-loss source wired up this
# pass, and 0 is a real, reachable state there (BattleController._check_
# battle_end() reads it as defeat). A non-combat, never-fatal loss (a
# field hazard, say) would need its own floored-at-1 mutator, same as the
# old project's own lose_hp()/take_damage() split - not needed yet, since
# nothing outside battle can cost HP this pass.
func lose_hp(amount: int) -> void:
	if amount <= 0:
		return
	player_hp = clampi(player_hp - amount, 0, player_max_hp)
	player_hp_changed.emit(player_hp, player_max_hp)

func heal(amount: int) -> void:
	if amount <= 0:
		return
	player_hp = mini(player_hp + amount, player_max_hp)
	player_hp_changed.emit(player_hp, player_max_hp)

# Clamps player_hp down if the new ceiling falls below it; never raises
# player_hp on its own when the ceiling only rises - a higher max isn't
# free healing.
func set_max_hp(new_max_hp: int) -> void:
	player_max_hp = new_max_hp
	player_hp = mini(player_hp, player_max_hp)
	player_hp_changed.emit(player_hp, player_max_hp)

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)

# True when there was enough and it was taken, false when there wasn't
# and nothing changed - so a caller can't half-spend by checking the
# total itself and racing something else.
func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true

# The run's one card-grant path (rewards, the Keeper's offer, a find on
# the sand). The deck holds a COPY, never the pool's own resource - the
# same way new_run() copies each starter - so two grants of one card are
# two cards: everything that tracks cards by identity (Deck's piles,
# HandContainer's slots, remove_card() below) counts on every entry
# being its own object. Appending the shared resource twice made the
# hand lose a slot each time the second copy was drawn.
func add_card(card: CardData) -> void:
	deck.append(card.duplicate() as CardData)
	deck_changed.emit()

func remove_card(card: CardData) -> void:
	deck.erase(card)
	deck_changed.emit()
