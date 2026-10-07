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
# The new total, like gold_changed.
signal glassbone_changed(amount: int)
# The new total, like gold_changed.
signal toll_changed(amount: int)
# The keepsake slot changed - the new one, or null for empty.
signal keepsake_changed(keepsake: TrinketData)

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

# Glassbone, the one material: pieces taken this run, spent tempering
# cards at the wagon (temper_card()). Not money - gold is that.
# Carries across every fight and floor, as everything here does;
# new_run() starts it at 0. Mutated only through add_glassbone()/
# spend_glassbone(), so it never goes below 0 and the readout always
# hears.
var glassbone: int = 0

# The Wanderer's Toll. It carries from one combat to the next - won or
# escaped - and across a floor advance, but only up to the character's
# toll_carry_cap: each fight's end and each floor advance keep min(Toll,
# cap) (carry_toll()). In a fight it runs free. new_run() starts it at 0.
# The one copy - the player's Combatant reads and writes this through its
# own toll property (see Combatant.run_toll_owner), so no battle-end path
# has anything to write back. Mutated only through set_toll().
var toll: int = 0

# The one keepsake slot - a TrinketData, or null. Never more than one:
# a second is a choice (take it and leave this, or keep this and leave
# it - KeepsakeOffer), never a stack. Survives every fight and floor, as
# everything here does; new_run() empties it. Changed only through
# equip_keepsake().
var keepsake: TrinketData = null
# The ids of every keepsake offered this run, taken or left - what a
# unique_per_run table entry is kept out by (KeepsakeTable.roll()).
var keepsakes_offered: Array[StringName] = []
# HP actually lost since the fight in progress (or the last one) opened -
# what lose_hp() really took, never the damage that was attempted, from
# any source: an enemy's hit, the Wanderer's own self-damage, a status
# tick. Zeroed by begin_combat() from BattleController.setup(); read by
# settle_keepsake_win() for heal_on_win_after_loss.
var hp_lost_this_combat: int = 0

var character: CharacterData = null

var current_region_index: int = 0
var current_floor_index: int = 0
# How many times this run has gone round the region - its last floor
# wraps to the first only with RegionField.loop_region_after_last_floor
# (otherwise leaving it ends the run, won). For the run log's
# floor_entered; new_run() zeroes it.
var region_lap: int = 0
# The run's tally for its end (RunEnd's stats, the log's run_end): floors
# left by their exit - the last one too, so a straight run of Region 1 is
# 5 - and fights won (RegionField's WIN outcome, debug wins included).
# new_run() zeroes both.
var floors_crossed: int = 0
var fights_won: int = 0
# How the run ended (log_run_end()'s cause: won, died, drowned, quit,
# abandoned), "" while it runs - what RunEnd reads to say the line for a
# drowning. new_run() clears it.
var end_cause: String = ""

# The zone intro (ZoneIntro, played by RegionField) is owed exactly once,
# by the first floor of a NEW run: new_run() raises this and RegionField
# consumes it (reads and clears) in its _ready(). A floor change
# (reload_current_scene()) never calls new_run(), so it never raises it -
# the intro is a run's first frame, not a floor's. The end screen's NEW
# RUN does call new_run() (RunEnd._activate()): a new run.
var run_opening_pending: bool = false

# Raised by the boot scene (TitleScreen) alone, consumed by RegionField's
# _ready(): the field holds the title (ZoneIntro.hold_title() - the intro's
# frame zero with the TitleMenu over it) instead of playing the intro
# outright. F6 on the field and the end screen's NEW RUN never raise it.
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
	# A run never ended (a probe's second run, say) is closed first.
	if RunLogger.is_run_open():
		log_run_end("abandoned")
	character = starting_character
	# Fresh seed per run, recorded rather than thrown away. randi() is
	# fine as the SOURCE of a seed - it's the one roll that doesn't need
	# to be reproducible, since it's what makes the rest of them so.
	run_seed = randi()
	rng.seed = run_seed
	gold = 0
	glassbone = 0
	toll = 0
	keepsake = null
	keepsakes_offered.clear()
	hp_lost_this_combat = 0
	player_max_hp = starting_character.max_hp
	player_hp = player_max_hp
	deck = _build_starting_deck(starting_character)
	current_region_index = 0
	current_floor_index = 0
	region_lap = 0
	floors_crossed = 0
	fights_won = 0
	end_cause = ""
	# Field findings (a Hull's one-time world line, a Bird's one-time
	# flight, the Keeper's one-time offer, a belongings cache's one
	# choice, a trough's one drink) are remembered per run in their own
	# static sets - see Hull._findings_shown / Bird._flown / Keeper._
	# offers_made / BelongingsCache._spent / TroughProp._drunk - so a new
	# run starts with none of them spent.
	Hull.reset_findings()
	Bird.reset_flights()
	Keeper.reset_offers()
	BelongingsCache.reset_spent()
	TroughProp.reset_drunk()
	# The LINE exit's world line is said once per run, the same way - see
	# RegionField.hold_line_world_line.
	RegionField.reset_hold_line_spoken()
	run_opening_pending = true
	player_hp_changed.emit(player_hp, player_max_hp)
	deck_changed.emit()
	gold_changed.emit(gold)
	glassbone_changed.emit(glassbone)
	toll_changed.emit(toll)
	keepsake_changed.emit(keepsake)
	RunLogger.start_run(run_seed, starting_character.character_name, run_snapshot())

# The run as the log records it (RunLogger): HP, purse, Toll, the deck as
# card counts, the keepsake's id, and where in the run.
func run_snapshot() -> Dictionary:
	var counts: Dictionary = {}
	for card in deck:
		counts[card.card_name] = int(counts.get(card.card_name, 0)) + 1
	return {
		"hp": player_hp,
		"max_hp": player_max_hp,
		"gold": gold,
		"glassbone": glassbone,
		"toll": toll,
		"deck_size": deck.size(),
		"deck": counts,
		"keepsake": RunLogger.keepsake_id(keepsake),
		"region": current_region_index,
		"floor": current_floor_index,
		"lap": region_lap,
		"floors_crossed": floors_crossed,
		"fights_won": fights_won,
	}

# The run is over, for the log: won, died, drowned, quit or abandoned.
func log_run_end(cause: String) -> void:
	end_cause = cause
	RunLogger.end_run(cause, run_snapshot())

# The window closing is a quit - the line goes before the tree does.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		log_run_end("quit")

# The tree going without a run_end written (a quit that didn't come
# through the window's close): "stopped". Nothing when one was - the log
# closes its file on a run_end. The editor's Stop kills the process before
# this can run; RunLogger closes those runs when the next one starts.
func _exit_tree() -> void:
	if RunLogger.is_run_open():
		log_run_end("stopped")

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
	var before: int = player_hp
	player_hp = clampi(player_hp - amount, 0, player_max_hp)
	hp_lost_this_combat += before - player_hp
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

func add_glassbone(amount: int) -> void:
	if amount <= 0:
		return
	glassbone += amount
	glassbone_changed.emit(glassbone)

# spend_gold()'s contract: all of it or nothing.
func spend_glassbone(amount: int) -> bool:
	if amount <= 0 or glassbone < amount:
		return false
	glassbone -= amount
	glassbone_changed.emit(glassbone)
	return true

# Toll between fights: what's held, down to the character's toll_carry_
# cap if it's over. Called as each fight ends (RegionField._on_battle_
# finished(), any outcome) and at the floor advance (RegionField._on_
# floor_exited()). Nothing without a character.
func carry_toll() -> void:
	if character == null:
		return
	set_toll(mini(toll, maxi(character.toll_carry_cap, 0)))

# Floored at 0: an overspend clamps rather than leaving a debt. Emits only
# on a real change.
func set_toll(value: int) -> void:
	var clamped: int = maxi(value, 0)
	if clamped == toll:
		return
	RunLogger.toll_changed(toll, clamped)
	toll = clamped
	toll_changed.emit(toll)

# The slot's one mutator: `trinket` in, whatever was there left behind.
# null empties it. Emits only on a real change.
func equip_keepsake(trinket: TrinketData) -> void:
	if trinket == keepsake:
		return
	keepsake = trinket
	keepsake_changed.emit(keepsake)

# Acquiring a keepsake: an empty slot takes it at once (true); a full one
# changes nothing (false) - the caller offers the take-or-keep choice.
func acquire_keepsake(trinket: TrinketData) -> bool:
	if trinket == null or keepsake != null:
		return false
	equip_keepsake(trinket)
	return true

# A keepsake has been put in front of the player - remembered for the
# run whether they take it or not (see keepsakes_offered).
func note_keepsake_offered(trinket: TrinketData) -> void:
	if trinket != null and not keepsakes_offered.has(trinket.id):
		keepsakes_offered.append(trinket.id)

# A fight is opening: nothing lost in it yet.
func begin_combat() -> void:
	hp_lost_this_combat = 0

# A fight was won (not escaped): the keepsake's heal_on_win, and its
# heal_on_win_after_loss if the fight actually cost HP - one heal, so the
# max-HP cap applies to the sum. Called by RegionField._on_battle_
# finished()'s WIN branch.
func settle_keepsake_win() -> void:
	if keepsake == null:
		return
	var amount: int = keepsake.heal_on_win
	if hp_lost_this_combat > 0:
		amount += keepsake.heal_on_win_after_loss
	var before: int = player_hp
	heal(amount)
	RunLogger.player_healed(player_hp - before, "keepsake:" + String(keepsake.id))

# The run's one card-grant path (rewards, the Keeper's offer, a find on
# the sand). The deck holds a COPY, never the pool's own resource - the
# same way new_run() copies each starter - so two grants of one card are
# two cards: everything that tracks cards by identity (Deck's piles,
# HandContainer's slots, remove_card() below) counts on every entry
# being its own object. Appending the shared resource twice made the
# hand lose a slot each time the second copy was drawn. Returns that
# copy, for a caller that must put the same instance into a fight too.
func add_card(card: CardData) -> CardData:
	var copy := card.duplicate() as CardData
	deck.append(copy)
	deck_changed.emit()
	return copy

func remove_card(card: CardData) -> void:
	deck.erase(card)
	deck_changed.emit()

# Tempering (the wagon - WagonScreen): `cost` Glassbone for `card`'s
# tempered version (CardData.tempered), a fresh copy at the same place in
# the deck - its own object, as add_card()'s copies are, so a later
# Consumed removal finds it by identity like any other card. Between
# fights only: no fight's piles hold the old card. All or nothing, on
# spend_glassbone()'s terms (a cost under 1 is refused): null, with
# nothing spent, when the card isn't in the deck, has no tempered
# version, or the Glassbone isn't there. Returns the new card.
func temper_card(card: CardData, cost: int) -> CardData:
	if card == null or card.tempered == null:
		return null
	var index: int = deck.find(card)
	if index < 0:
		return null
	if not spend_glassbone(cost):
		return null
	var copy := card.tempered.duplicate() as CardData
	deck[index] = copy
	deck_changed.emit()
	RunLogger.event("temper", {"card": card.card_name, "tempered": copy.card_name, "glassbone_after": glassbone})
	return copy
