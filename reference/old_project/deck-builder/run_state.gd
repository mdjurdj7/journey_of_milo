extends Node
# This script becomes a "singleton" the moment it's registered as an
# autoload (see project.godot's [autoload] section, or Project > Project
# Settings > Autoload in the editor). Godot creates exactly one instance
# of it automatically when the game starts, adds it to the scene tree
# before any other scene loads, and keeps it alive for the entire game
# session - including through scene changes, once we have more than one
# scene. Any script anywhere in the project can then just write
# `RunState.player_hp` and reach this exact same instance, with no
# @onready reference, no instancing, no passing it around as an argument.
#
# That's a different pattern from CardData/EnemyData/Card/Enemy, which
# all use `class_name` to register a *type* you can make many instances
# of (many Cards, many CardData resources). RunState is the opposite:
# not a type to instance, but one specific, always-there object - which
# is why it has no class_name here, just the autoload name "RunState"
# (set in Project Settings, mirrored in project.godot) that IS its global
# identifier.
#
# What belongs here vs. elsewhere: RunState holds only what must survive
# PAST a single battle OR a single field room ending - the player's HP
# carrying scars from fight to fight, which battle number and room
# number the run is on, accumulated gold, and the run's deck composition
# (which cards you own, including any picked up as rewards). Everything
# that gets rebuilt fresh every fight (energy, block, the current enemy,
# the turn counter, and the draw/hand/discard piles - which cards are
# WHERE during this particular battle) stays local to Battle, because
# Battle's own state is thrown away and rebuilt each fight and shouldn't
# survive a battle ending. Similarly, everything specific to the CURRENT
# field room (which blobs in it are dead, whether its chest is open, where
# the player was standing) lives in RoomState (see room_state.gd), not
# here - that's room-instance state, thrown away and rebuilt fresh every
# time a new room is generated, the same relationship Battle has with
# RunState. This split is what makes a run built from many rooms and many
# battles possible without any of those pieces needing to know or care
# what happened in the one before it.

# Registered as a scene autoload (run_state.tscn), not a bare script one,
# for the same reason RoomState is (see room_state.gd's comment on its own
# @export weights): the run-graph generation parameters below are things
# we expect to tune, and @export only shows up in the Inspector when the
# autoload has a scene to attach to.

const DEFAULT_PLAYER_MAX_HP := 70

const SLASH := preload("res://resources/cards/slash.tres")
const BITE_DOWN := preload("res://resources/cards/bite_down.tres")
# Named "Blood Tithe" until 2026-08-27, then "Overreach" until
# 2026-08-28 - same card, `card_name` and the resource filename renamed
# to match each time (see DESIGN.md's Wanderer entry). Quick Slash used
# to fill this third starting-deck slot; removed from the game entirely
# (2026-08-24), not just moved to the reward pool like Heavy Blow/Focus
# were - it was a 0-cost attack with no chain identity that diluted
# draws without teaching anything. Bite Down replaces it (2026-08-24)
# as the deck's IDENTITY card, not a filler slot - see DESIGN.md's
# Starting deck note and the Wanderer's own Characters entry for why
# this specific card matters: it always costs 2 HP when played
# (chain_role is OPENER now, but it carries no payoff of its own - the
# 2026-08-26 "chain payoff: REVERSED" change, see DESIGN.md, removed the
# self-refund it briefly had back when it was a Closer), teaching "this
# character pays for power" from the very first fight, unconditionally.

const BRACE := preload("res://resources/cards/brace.tres")
const DOWN_PAYMENT := preload("res://resources/cards/down_payment.tres")
const RECKONING := preload("res://resources/cards/classes/wanderer/reckoning.tres")
# Reckoning is ALSO a live reward-pool card (resources/cards/classes/
# wanderer/ - see CardPool.load_class_pool()'s own scan folder) -
# preloading it here for the starter deck doesn't pull it out of that
# pool or duplicate the resource anywhere; a run can still draft a
# SECOND copy from a reward/shop roll on top of the one guaranteed here,
# same as any other class-pool card's own upgrade path. One resource,
# two independent ways to end up owning a copy of it - deliberate, not
# an oversight (2026-09-05, starter-deck rework).

const WANDERER := preload("res://resources/characters/wanderer.tres")
const SAMURAI := preload("res://resources/characters/samurai.tres")
# The full class roster. There's no character-select screen yet, so
# reset() below just hardcodes which one a run starts as - swapping that
# one line for a real selection later is the only change a select screen
# will need here. SAMURAI (chain/combo class built on the OPENER/CLOSER
# system - see card_data.gd's ChainRole) started as "Rogue" (renamed
# 2026-09-03); its card pool is deliberately empty for now.

# --- Starting deck config ---
#
# THE starting deck, in one place: every new run's deck begins as exactly
# this - edit this dictionary (which CardData, how many copies) to tune
# the composition; nothing else in this file needs to change to match.
# Keys are the preloaded CardData resources above, values are copy count.
const STARTING_DECK: Dictionary = {
	SLASH: 3,
	BITE_DOWN: 2,
	BRACE: 2,
	RECKONING: 1,
	DOWN_PAYMENT: 1,
}

var current_class: CharacterData = WANDERER
# Which class this run's player is. Only source of "player has a class"
# right now - no character-select UI exists yet, so this just starts at
# a hardcoded default (see reset() below) rather than being chosen.
# reward_screen.gd's _load_reward_pool() scans current_class.card_pool_
# folder to build this class's (and only this class's) reward offers
# (see character_data.gd).

const SUNKEN_WORKS := preload("res://resources/biomes/sunken_works.tres")
# The full biome roster - same "const preload, reset() picks the
# default" shape as WANDERER/SAMURAI above. Only one biome exists so far
# (see DESIGN.md's Biomes section), so this isn't a real choice yet
# either - swapping current_biome's default (or making it a real
# per-run pick) is the only change a future second biome or a biome-
# select mechanic would need here.

var current_biome: BiomeData = SUNKEN_WORKS
# Which biome this run's rooms/battles belong to. battle.gd reads this
# to pick which biome's battle_backdrop (or Battle Background's own
# palette-driven fallback, if that's unset) to show behind a fight - see
# its _apply_battle_backdrop().

var player_max_hp: int = DEFAULT_PLAYER_MAX_HP
var player_hp: int = DEFAULT_PLAYER_MAX_HP
var battle_number: int = 1
var room_number: int = 1
var gold: int = 0

var shards: int = 0
# Upgrade shards (2026-09-02, forge pass) - a second run-scale currency,
# alongside gold: 1 shard = 1 card upgrade, spent at a FORGE room (see
# field_forge.gd) via CardUpgradeService.offer_upgrade(). Same "own field,
# own signal, own gain/spend pair" shape gold already uses (see add_
# shards()/spend_shards() below) rather than folding this into gold or a
# generic currency dict - shards and gold are spent in unrelated places
# (a forge, a shop) and there's no reason for one to imply anything about
# the other. Shard PICKUPS in the world are out of scope for this pass
# entirely (see DESIGN.md/this pass's own brief) - add_shards() exists and
# works, but nothing in the field grants any yet; RunState.add_shards() is
# reachable only through a dev tool for now.

# Whether the run's first real fight has been generated yet - set once, by
# RoomState._generate_combat_layout() (see its own note on where the
# Tideworn pin actually lives), the first time it builds a combat room's
# first blob. Lives here rather than as a bool local to that function
# because "has the player had their first fight yet" is run-wide state,
# not room-generation-time state - RoomState.reset_room() clears on every
# room load, which would make this true only within a single room. Not
# the same question as "is current_node the opening room" (opening_node
# never fights anyone any more - see room_state.gd's own "quiet arrival
# room" pass) or "is current_node.layer == 0" (a layer can roll TREASURE/
# EVENT/SHOP/ELITE, so the run's first COMBAT room can land on any layer,
# not just the first one) - this is the one flag that actually tracks
# what it needs to: has ANY combat room's content been rolled yet, this
# run, regardless of which layer it turned out to be.
var first_combat_generated: bool = false

var equipped_weapon: WeaponData = null
# One slot, one field - not a slot dictionary/enum system built ahead of
# need. See DESIGN.md's Equipment note: armor/trinket, if they happen,
# arrive later as sibling fields (equipped_armor/equipped_trinket)
# following this exact same shape, the same "parallel fields, not one
# polymorphic system" pattern pending_enemy_data/pending_encounter_
# enemies below already use - purely additive, nothing about this field
# would need to change. Starts null every run (see reset() below) - "no
# weapon" is a completely legal, expected state, not a missing-data bug
# (same "empty means unaffected" shape everywhere else in this project).

var equipped_trinket: TrinketData = null
# The predicted sibling field, arrived (2026-08-28) - see equipped_
# weapon's own comment above, written before this existed. Exactly the
# same shape: one slot, starts null every run, "no trinket" is a
# completely legal state. No pickup/loot/reward/deck-viewer UI grants
# this yet (see trinket_data.gd's own scope note) - the only writer today
# is title_screen.gd's debug-only grant on the Dev Battle Chain shortcut.

var npc_interacted: Dictionary = {}
# Which NPCs this run's player has already accepted an offer from, keyed
# by NPCData.npc_id (see its own doc for why the key lives there) -
# true once accepted, absent/false otherwise. Run-scoped like deck/gold
# above, not room-scoped like RoomState.structure_resolved, since an
# NPC's own resolved state is meant to survive independent of whether
# her room ever gets revisited (see npc_data.gd's own header for this
# exact reasoning, written before this field existed to hold it).
# field_room.gd is the only reader/writer (see its _accept_npc_offer()).

var opening_room_hull_line_shown: bool = false
# Whether this run has already fired the opening room's positional world-
# voice line (the boat-hull observation the player crosses a world-x
# threshold to trigger - see field_room.gd's own _update_opening_room_
# hull_line()/_play_opening_room_hull_line()) - run-scoped, same "survives
# a revisit, cleared only on a fresh run" shape npc_interacted above
# already uses, and for the same underlying reason: crossing back and
# forth over the threshold within one run must not re-fire it. field_
# room.gd is the only reader/writer.

var event_content_generated: Dictionary = {}
# Which specific EVENT contents this run has generated so far, and how
# many of each - Dictionary of content-id (String) -> count, read/
# written entirely from RoomState's own _generate_event_layout() (2026-
# 08-28, second-event pass), not from any code in this file. Same cross-
# file split first_combat_generated above already establishes: a run-
# scoped "has this happened yet" tracker lives here, on RunState, because
# it has to persist across every room a run generates, but the code that
# actually consults and mutates it lives alongside the room-content
# generator that needs it, not here. See RoomState.event_content_max_
# instances for the per-content-id cap this count is checked against.

var sift_outcomes_drawn: Array[int] = []
# Which entries of the wreckage heap's SiftOutcomeTable (see sift_
# outcome_table.gd) this run has already drawn, by array index - draw
# without replacement, shared across every heap visited this run, same
# "run-scoped, survives a revisit" shape npc_interacted above already
# uses. Indices, not the SiftOutcomeData resources themselves, since the
# table is one shared, never-mutated .tres every heap instance points at
# (see field_heap.gd's own sift_outcome_table export) - an index is
# stable for as long as that one resource's entries array is, and is
# trivially serializable if a save system ever needs this later. Read/
# written only by SiftOutcomePool.draw() (2026-08-28, wreckage-heap room
# v1) - once every index has been drawn, further pulls stop being offered
# rather than reshuffling (this feature's own brief).

var card_removals_purchased: int = 0
# How many times the SHOP's "Remove a Card" service has been bought this
# run - shop_window.gd reads this to scale the next removal's price up
# (see its removal_price_increment) rather than charging a flat amount
# every time. Run-scoped, not room-scoped, since a run only guarantees
# one SHOP node total (see the run graph note below) - this is what makes
# "scales per run" and "scales per shop visit" the same thing in practice
# today, but it's tracked at the RunState level on purpose in case a
# future run ever has more than one shop.

# Announced whenever gold changes, so a display (GoldDisplay - see
# gold_display.gd) can stay accurate without whatever GRANTED the gold
# (a field chest, a reward, eventually a shop) needing to know a display
# exists at all - same "the display reacts, the source doesn't have to
# know who's watching" idea as every signal already in this project.
# Every gold-granting call site should go through add_gold() below rather
# than mutating `gold` directly, or this signal (and anything relying on
# it) silently stops being accurate.
signal gold_changed(new_amount: int)

# The upgrade-shard mirror of gold_changed above (2026-09-02, forge pass) -
# same "the display reacts, the source doesn't have to know who's
# watching" reasoning, even though no display consumes this yet (a shard
# HUD counter is explicitly out of scope for this pass - see add_shards()/
# spend_shards() below). Emitted for the same reason gold_changed is: so
# a future display never has to be threaded through every shard-granting/
# spending call site individually.
signal shards_changed(new_amount: int)

# The HP mirror of gold_changed/shards_changed above (2026-09-05, HP-
# signal pass) - same "the display reacts, the source doesn't have to
# know who's watching" idea. Carries new_max_hp alongside new_hp (unlike
# gold/shards, which have no accompanying cap) so a subscriber gets
# everything a VitalsBar's update_hp(current, max) call needs from ONE
# signal, without a second read back into RunState. Every player_hp-
# changing call site should go through take_damage()/lose_hp()/heal()
# below rather than mutating `player_hp` directly, or this signal (and
# anything relying on it - see run_hud.gd/player_battle_visual.gd/field_
# interior.gd's own subscriptions) silently stops being accurate.
signal player_hp_changed(new_hp: int, new_max_hp: int)

# The mirror of player_hp_changed above, for max_hp changing on its own
# (set_max_hp() below can fire this independently of player_hp_changed,
# when raising the ceiling doesn't also move current HP - see that
# function's own doc for why it never does). Every player_max_hp-changing
# call site should go through set_max_hp() rather than mutating
# `player_max_hp` directly, for the same reason gold_changed's own doc
# gives.
signal player_max_hp_changed(new_max_hp: int)

# The run's deck composition: which CardData resources you own and how
# many copies. This is the source of truth Battle copies from at the
# start of every fight (see battle.gd's _start_battle()) - Battle
# shuffles and draws its OWN copy, so nothing it does to that copy during
# a fight (discarding, drawing) touches this array.
var deck: Array[CardData] = []

# --- Run graph ---
#
# THE SPINE: the graph decides every room's type before the player ever
# sees it. field_room.gd reads current_node.connections to know how many
# doors this room has and where each leads (see its _spawn_exits()), and
# field_exit.gd advances current_node the instant the player walks
# through whichever door they chose (see its _on_body_entered()).
# RoomState still owns a ROOM's own contents once it knows the type (see
# room_state.gd) - this is only about which type each room in the graph
# gets, and how they connect to each other.

@export var layer_count: int = 9
# LOWERED from 11 (2026-08-28, run-length pass) - a playthrough visits
# exactly 1 (the prepended opening room) + this many rooms (one per
# layer; branching affects CHOICE, not depth - see _connect_layers()'s
# own doc), so 11 meant 12 rooms per run, not 11. 9 means 10. shop_min_
# layer/shop_max_layer below were rescaled alongside this (same
# fractional window of the run, not the same absolute layer numbers) -
# see that export's own doc for the math. elite_layer_count_min/_max/
# elite_layer_min_gap/elite_excluded_post_opening_layers were NOT
# touched - all four are flat counts (how many layers, how far apart,
# how many EARLIEST layers to skip), not fractions of the run, so they
# don't need rescaling; _reserve_elite_layers()'s own max_feasible clamp
# already handles a shorter run offering fewer eligible layers than
# elite_layer_count_max asks for. combat_weight/treasure_weight/event_
# weight were NOT touched either - those are ratios among LEFTOVER
# nodes, not counts, so they already scale proportionally for free as
# this shrinks or grows.
@export var min_layer_size: int = 1
@export var max_layer_size: int = 4
# RAISED max from 3, LOWERED min from 2 (2026-08-28, width-variety pass) -
# min_layer_size = 2 used to block single-node chokepoints entirely; at 1,
# a layer can now genuinely narrow to one room before widening again, not
# just vary between "kind of wide" and "wide." Layers 0 and layer_count -
# 1 are still always forced to size 1 (start and boss) regardless of
# these two - see _build_empty_layers() - so this range only ever governs
# the layers between them.
#
# Layer sizes: map_screen.gd's own row layout (_build_map()/_rows()) is
# fully width-generic regardless of any of this - row.size() drives node
# x-spacing and canvas width directly, nothing assumes 2-3. Verified
# headlessly against real 1-wide and 4-wide rows from the width-variety
# pass's own sampling (see that pass's report). Note that a 4-wide layer
# is only ever reachable from a predecessor with real spare capacity
# (size * max_forward_edges >= 4) - see max_forward_edges' own doc below
# for exactly which predecessor sizes that includes at the current cap.

@export var layer_size_1_weight: float = 10.0
@export var layer_size_2_weight: float = 40.0
@export var layer_size_3_weight: float = 42.0
@export var layer_size_4_weight: float = 8.0
# RETUNED from 10/40/40/10 (2026-08-28, density-reduction pass) - a
# density complaint (the graph reading as too visually busy) traced back
# to two things: the edge cap (see max_forward_edges' own doc, lowered in
# the same pass) and 4-wide layers showing up as often as 2-wide ones did
# under the old 10/40/40/10 split. Moving those 2 points from 4_weight to
# 3_weight keeps the total unchanged (100) while making 4 noticeably
# rarer than 2 (8% vs 40% of an unconstrained roll) without touching how
# common a chokepoint is (1_weight untouched) or meaningfully changing
# 2-vs-3's own relative split (40:42 instead of 40:40 - barely moved,
# not the point of this retune). _pick_layer_size() below still rolls via
# WeightedRandom.pick() using these four, NOT a uniform randi_range() -
# uniform over [1,4] would make a chokepoint or a 4-wide layer a full
# quarter of every roll, which reads as "coin flip," not "uncommon." The
# chokepoint-adjacency rule below (see its own doc) excludes 1 entirely
# from some layers' rolls, so the REALIZED chokepoint rate per layer ends
# up somewhat below 10% in practice (see this pass's own report for the
# actual re-sampled numbers, confirming this retune didn't shift it).
# Each its own export, not a single weights array/dictionary, so a
# size's own likelihood is a plain Inspector number, the same "one knob
# per named thing" shape every other export here already follows, rather
# than editing dictionary literals in code.

@export var max_forward_edges: int = 2
# LOWERED from 3 (2026-08-28, density-reduction pass) - the run map was
# reading as too visually dense: at 3, a majority of layer transitions
# ended up FULLY bipartite (every source connected to every target -
# see this pass's own report for the exact sampled rate), which is a lot
# of crossing lines for very little real branching MEANING (see the
# width-variety pass's own investigation: full bipartite connectivity
# makes path choice largely cosmetic). At 2, a source can still offer a
# real binary choice (this room OR that one) without also being able to
# blanket-connect to 3-4 targets at once.
#
# Consequence worth naming plainly: a 1-wide chokepoint's own immediate
# successor layer is capped at (1 * this) = 2 - it was ALREADY capped
# below 4 even at the old max_forward_edges=3 (1*3=3, still short of 4),
# so this change doesn't newly break a "chokepoint directly feeds a
# 4-wide layer" case - that specific direct adjacency was never possible
# in the first place, at either value. A 4-wide layer is still reachable
# two steps after a chokepoint (chokepoint -> capped-at-2 recovery layer
# -> up to 2*2=4 the layer after that), just never immediately after one.
#
# Hard cap on how many forward edges a single graph node can have - every
# node gets between 1 and this many (see _connect_layers()). Purely a
# graph-structure knob now (DESIGN.md's field movement redesign:
# navigation redesign step 1) - field_room.gd always renders exactly ONE
# door per room regardless of this value, temporarily just following the
# first edge when there's more than one (see its _spawn_exits()); a real
# map screen, not a second door, is how branching becomes visible/
# choosable again.

@export var shop_min_layer: int = 3
@export var shop_max_layer: int = 7
# 1-indexed (matches how layers print and read in DESIGN.md) - the single
# guaranteed SHOP node is placed somewhere in this inclusive range.
#
# RESCALED from 4-8 (2026-08-28, run-length pass, layer_count 11 -> 9) -
# 4-8 covered layers [(4-1)/11, 8/11] = [27%, 73%] of an 11-layer run
# (the middle half, per the ORIGINAL 8-layer pass this window traces
# back to). Recomputed against THAT fraction, not the old absolute
# numbers, so the window still covers the same middle-of-the-run PORTION
# rather than covering a different slice of a shorter run: round(0.25 *
# 9) + 1 = 3, round(0.75 * 9) = 7 -> layers 3-7, [22%, 78%] of 9 - same
# window, just relocated to match the new length.

@export var elite_layer_count_min: int = 2
@export var elite_layer_count_max: int = 4
# How many DISTINCT LAYERS get an elite reserved onto them, picked once
# per run (see _reserve_elite_layers(), called from _assign_room_types())
# - 2-4 by default. This counts LAYERS, not nodes: a layer promoted to a
# second, side-by-side elite (see elite_side_by_side_promotion_chance
# below) still only counts once here.
#
# REPLACES the old elite_count_min/_max + elite_min_layer/_max_layer pair
# (2026-08-28, guaranteed-elite-layers pass) - the previous scheme picked
# ELITE nodes via one flat shuffle-and-slice over every candidate node in
# the eligible layer window, with nothing constraining which LAYERS those
# nodes landed on - a run could (rarely, but really) land 3 of its 4
# elites in one layer and 0 in the next few, which reads as "the map is
# just an elite gauntlet here" rather than a spaced-out routing choice.
# This pass reserves LAYERS first, with guaranteed spacing (see
# elite_layer_min_gap below), and lets normal type assignment fill in
# around whatever got reserved.

@export var elite_layer_min_gap: int = 2
# Minimum LAYER-INDEX distance between any two chosen elite layers - 2
# means two chosen layers can never be adjacent (1 apart is forbidden, 2+
# apart is fine). Enforced by construction in _select_elite_layers()
# below, not by rolling and rejecting anything that violates it.

@export var elite_excluded_post_opening_layers: int = 2
# How many of run_graph's own EARLIEST layers are excluded from elite
# eligibility, on top of the boss's own always-excluded final layer - an
# elite immediately after the (separately prepended, always-COMBAT)
# opening room is a coin flip before the player's deck has any real
# shape yet, not a real difficulty spike. 2 means run_graph layers 0 and
# 1 (the first two layers generated AFTER the opening room, which itself
# lives outside run_graph entirely - see opening_node's own doc) are
# never eligible.

@export var elite_side_by_side_promotion_chance: float = 0.15
# Once a layer is reserved as an elite layer, a layer with more than one
# node has this chance of getting a SECOND node in it promoted to ELITE
# too - still counts as ONE elite layer toward elite_layer_count_min/_max
# (that count is layers, not nodes - see its own doc), just a slightly
# scarier one to route around (DESIGN.md's ELITE Rooms note: elites are a
# routing choice, never a forced encounter - a layer where every node is
# ELITE would break that). Low by design so it reads as an occasional
# surprise, not a common pattern.

@export var event_enabled: bool = false
# Single on/off switch for EVENT room generation (2026-09-07, EVENT-
# disable pass) - EVENT was built for the payhouse, which is no longer
# this game's direction, and field_marker.gd's own EVENT branch is still
# just a bare print() with no real content behind it today. Gates BOTH
# of the two places a node could ever become EVENT in _assign_room_
# types() below: the guaranteed-one pick_random() call, and event_
# weight's own entry in the leftover roll's weights dict - false means
# neither ever runs, so no node in a freshly generated run graph can end
# up EVENT. Deliberately a single flag rather than deleting RoomType.
# Kind.EVENT, the field_marker.gd branch, or the room icon - events are
# still in the design as findings rather than incidents (not the
# payhouse concept this flag actually disables), so re-enabling should
# mean flipping this back to true, not rebuilding any of that from
# scratch.
#
# Confirmed safe to flip off on its own (2026-09-07 investigation, no
# code changed to verify this): _validate_run_graph() tracks no EVENT
# count at all (SHOP is the only type checked for an exact count), room_
# type_min_instances has no EVENT entry to remove, and the run graph's
# own SHAPE (layer_count, _pick_layer_size()) is fixed before room types
# are ever assigned - disabling one type can't shrink the ~12-room
# target, it just leaves those nodes for COMBAT/TREASURE/HEAP/FORGE's
# own existing weights to fill instead, at their existing relative
# proportions (unchanged here - see this pass's own report for the
# actual numbers).
@export var combat_weight: float = 60.0
@export var treasure_weight: float = 15.0
@export var event_weight: float = 10.0
@export var heap_weight: float = 10.0
@export var forge_weight: float = 15.0
# TEMPORARILY ABOVE heap_weight (2026-09-02, forge pass, RAISED same-day
# from an original 6.0 - see DESIGN.md's own parked-decision note on this)
# - originally started BELOW heap_weight (a forge visit meant to read as
# rarer than a wreckage heap), which measured at ~50% of generated runs
# containing zero FORGE rooms. Until region-boundary forging exists as a
# second shard sink, that's a real problem, not just flavor: shards can
# strand with nowhere to spend them for half of all early playtests,
# contaminating economy tuning before the mechanic even gets exercised.
# 15.0 measured at 79% of 300 generated runs containing at least one
# FORGE (21% zero, 35% one, 44% two) - deliberately not pushed further
# toward "guaranteed" (an 18.0 sample hit 88% but pushed the 2-forge case
# to over half of all runs, past what "a forge is a find" should feel
# like). EXPECTED TO REVERT toward scarcity once region-boundary forging
# ships - this value is a stopgap for the shard-strands-with-no-sink
# problem, not a real balance opinion about how common a forge should be.
# Odds for whatever's left over once the guaranteed BOSS/SHOP/TREASURE/
# EVENT nodes are placed (see _assign_room_types()). No shop_weight here:
# SHOP is never part of this leftover roll, since "exactly one SHOP" only
# holds if nothing else can produce a second one. HEAP (2026-08-28,
# wreckage-heap room v1) and FORGE (2026-09-02) both join this same
# leftover roll rather than getting their own guaranteed-once placement
# the way TREASURE/EVENT do - HEAP is guaranteed a different way instead
# (see room_type_min_instances below); FORGE isn't guaranteed at all (no
# min_instances entry - a run can still land zero, just less often now).

@export var room_type_max_instances: Dictionary = {RoomType.Kind.HEAP: 2, RoomType.Kind.FORGE: 2, RoomType.Kind.TREASURE: 1}
# A GENERAL per-type cap on how many leftover-roll nodes (see the loop in
# _assign_room_types() below) may end up as a given RoomType.Kind across
# one run/biome - not a heap-specific special case: any Kind absent from
# this dictionary is uncapped, exactly as COMBAT/EVENT are today.
# HEAP was the only entry seeded at first (2026-08-28, wreckage-heap room
# v1 brief: "default to 2 per biome") - RunState.current_biome only ever
# covers one biome per run today (see its own doc), so "per biome" and
# "per run" are the same cap in practice until a run can ever span more
# than one. FORGE joined at the same cap (2026-09-02, forge pass) - no
# particular reasoning behind matching HEAP's own number specifically,
# just a reasonable starting ceiling for a second capped-but-not-
# guaranteed type; nothing about the enforcement loop below is heap- (or
# forge-) specific, a future third capped type just adds its own entry
# here.
#
# TREASURE: 1 (2026-09-05, treasure-cap pass) is a DIFFERENT shape from
# HEAP/FORGE's caps above - TREASURE already gets exactly one guaranteed
# placement (see _assign_room_types()'s dedicated pick_random() call), so
# this cap's only job is to stop the leftover roll from ever handing out a
# SECOND one on top of that guaranteed one. That only works because the
# guaranteed pick is now seeded into type_counts before the leftover loop
# runs (see the seeding lines right before that loop) - without that
# seeding, this cap would be inert (the guaranteed pick would be invisible
# to type_counts, letting the leftover roll still grant a second TREASURE).
# EVENT deliberately has NO entry here despite being guaranteed-once the
# same way - left uncapped for now so this pass doesn't reach beyond its
# actual ask.

@export var room_type_min_instances: Dictionary = {RoomType.Kind.HEAP: 1}
# The mirror image of room_type_max_instances above (2026-08-28, per-type
# minimum pass) - a GENERAL per-type floor, reserved by _reserve_minimum_
# instances() before the leftover weighted fill ever runs, not a heap-
# specific special case: any Kind absent from this dictionary has no
# guarantee at all, same as COMBAT/TREASURE/EVENT today (TREASURE/EVENT
# already get their own "exactly one" guarantee above, via a dedicated
# pick_random() call each - this dictionary is for guarantees beyond
# that shape, and doesn't need to duplicate them). HEAP is the only entry
# seeded so far ("the wreckage heap must appear at least once per run" -
# see the NPCs section's own field-interactables note in DESIGN.md) -
# min(1) sits comfortably under max(2) above, so a run can land 1 or 2
# HEAP rooms, never 0 and never more than 2. See _reserve_minimum_
# instances()'s own doc for what happens if a future entry's min ever
# exceeds its own max, or if total minimums ever exceed what a run has
# room for - neither is validated away, both are handled the same
# "clamp/warn, don't crash" way this generator's other constraints are.

var run_graph: Array[RunLayer] = []
# One RunLayer per layer, in order - run_graph[0].nodes is always a
# single start node, run_graph[run_graph.size() - 1].nodes a single boss
# node. RunLayer only exists because GDScript doesn't support nested
# typed arrays (see run_layer.gd) - conceptually this is "an array of
# arrays of RunNode."

# --- Opening room (DECIDED - see DESIGN.md's Run Structure & Navigation:
# opening room) ---
#
# A single dedicated node, prepended ahead of run_graph rather than
# generated AS run_graph[0] - deliberately kept OUTSIDE the layered array
# instead of bumping layer_count and renumbering every existing node, so
# _build_empty_layers()/_connect_layers()/_assign_room_types() (and every
# range they read - shop_min_layer/max, elite_excluded_post_opening_
# layers) stay completely untouched and keep meaning exactly what they
# always meant:
# "layers 3-6 of the GENERATED graph," not "3-6 rooms from the run's true
# start." That's what "shifted one layer deeper, generation unchanged"
# actually requires - if the existing nodes' own .layer values had moved,
# room_state.gd's _past_first_layer() (RunState.current_node.layer > 0)
# would also have silently started reading the OLD start layer as "past
# the first layer," letting its harder encounter_chance roll ambush what
# was supposed to still be the run's safe second fight.
#
# layer -1 (see RunNode._init()'s id formatting, +1'd for display) prints
# as "L0_0" - reads naturally as "before layer 1" in the dev graph print
# without needing a fake position inside run_graph itself. room_state.gd
# checks `RunState.current_node == RunState.opening_node` to special-case
# this ONE room's contents (always a single Thicket Stalker - see its
# _generate_combat_layout()) and reward_screen.gd checks the same
# reference to guarantee this one battle's card reward (see its
# _generate_loot()) - both mirror the existing `is_elite` check shape,
# just keyed off node identity instead of room_type, since this room's
# TYPE is ordinary COMBAT and can't tell it apart from any other combat
# room on its own.
var opening_node: RunNode

var current_node: RunNode
# Which graph node the room the player is standing in right now
# corresponds to.

# Builds a brand new graph: empty layers sized per the export vars above,
# wired together, then typed. Called once per run, from reset() below.
func _generate_run_graph() -> void:
	run_graph = _build_empty_layers()
	_connect_layers()
	_assign_room_types()
	opening_node = RunNode.new(-1, 0)
	opening_node.room_type = RoomType.Kind.COMBAT
	opening_node.display_name = "Longshore"
	# A per-node override (see RunNode.display_name's own doc), not a new
	# label mechanism - map_screen.gd's _node_label() already prefers this
	# over the plain type label whenever it's non-empty, so this is the
	# only line needed to make the opening room read as distinct from an
	# ordinary combat node on the map, while staying mechanically COMBAT.
	opening_node.connections = [run_graph[0].nodes[0]]
	current_node = opening_node
	_print_run_graph()
	_validate_run_graph()

func _build_empty_layers() -> Array[RunLayer]:
	var layers: Array[RunLayer] = []
	for layer_index in layer_count:
		var size := _pick_layer_size(layer_index, layers)
		var layer := RunLayer.new()
		for i in size:
			layer.nodes.append(RunNode.new(layer_index, i))
		layers.append(layer)
	return layers

# Layers 0 and layer_count - 1 (start and boss) are always exactly 1.
# Every other layer rolls a WEIGHTED size (see layer_size_1_weight/_2_/
# _3_/_4_weight above - NOT a uniform randi_range, which would make a
# chokepoint or a max-width layer a full quarter of every roll) - EXCEPT
# it's also capped at (predecessor's size * max_forward_edges). That cap
# matters because _connect_layers() below needs every node in this layer
# to receive at least one incoming edge from the previous layer, and a
# source can only ever have max_forward_edges outgoing ones - so a layer
# can never be bigger than its predecessor's total fan-out capacity, or
# some of its nodes would be structurally unreachable no matter what the
# connecting pass does. In practice this bites right after the start
# layer and right after any chokepoint (the only layers whose predecessor
# has size 1); every other predecessor has 2-4 nodes, giving it at least
# (2 * max_forward_edges = 4) capacity at the current default max_
# forward_edges = 2 - exactly enough to never clip a roll (max_layer_
# size is also 4), even though a 2-wide predecessor no longer has room
# to spare above that the way it did at the old max_forward_edges = 3.
# The cap only ever actually reduces a roll right after a size-1
# predecessor.
#
# Chokepoint adjacency (width-variety pass, 2026-08-28 - see this pass's
# own report for the exact rule as given): no two size-1 layers in a row,
# and no size-1 layer touching the boss layer or layer 1 (the very first
# rollable layer, right after the always-1 start). All three fall out of
# ONE check, deliberately, rather than three separate special cases:
# excluding 1 whenever the PREVIOUS layer's size is already 1 covers "no
# two chokepoints in a row" directly, and ALSO covers "layer 1 can never
# be a chokepoint" for free, since layer 0 (its predecessor) is always
# forced to size 1 regardless of any roll - previous_size == 1 is already
# true there without needing a separate layer_index == 1 check. "Not
# touching the boss layer" needs its own explicit check instead, since
# boss's own forced size isn't decided yet when its PREDECESSOR (layer_
# count - 2) is being picked here (layers are built strictly forward) -
# hardcoded against layer_count directly rather than looked up.
func _pick_layer_size(layer_index: int, layers_so_far: Array[RunLayer]) -> int:
	var is_endpoint := layer_index == 0 or layer_index == layer_count - 1
	if is_endpoint:
		return 1
	var previous_size := layers_so_far[layer_index - 1].nodes.size()
	var weights := {
		2: layer_size_2_weight,
		3: layer_size_3_weight,
		4: layer_size_4_weight,
	}
	var chokepoint_forbidden := previous_size == 1 or layer_index == layer_count - 2
	if not chokepoint_forbidden:
		weights[1] = layer_size_1_weight
	var size: int = WeightedRandom.pick(weights)
	return min(size, previous_size * max_forward_edges)

# Wires each layer to the next in three passes.
#
# Pass one guarantees reachability: every target in the next layer, in
# random order, is assigned to a random source that still has spare
# capacity (out-degree < max_forward_edges). This can never get stuck -
# _pick_layer_size() above guarantees the current layer's total capacity
# (its size * max_forward_edges) is always at least the next layer's
# size, and consuming capacity one target at a time never exceeds that
# total, so there's always at least one source with room left when the
# next target needs one.
#
# Pass two guarantees every source has its own edge: a source pass one
# never happened to pick (every target it could reach got covered by
# someone else first) still needs at least one outgoing edge to be a real
# node in the graph - which target it points at doesn't affect
# reachability (already guaranteed) or the cap (it's starting from 0).
#
# Pass three is variety, not correctness: sources sitting below the cap
# get a chance at another edge, so most rooms end up with a real
# branching choice instead of exactly one door by default. Capped short
# of full bipartite connectivity unless the widths force it - see
# _connect_one_transition()'s own doc on the cap for why.
#
# Together, every non-final node ending up with 1-max_forward_edges
# outgoing edges also makes "every path reaches the boss" automatic for
# free: edges only ever go from layer N to layer N+1, so any path forward
# from any node necessarily keeps advancing a layer at a time until it
# runs out of layers - which only happens at the boss.
func _connect_layers() -> void:
	for layer_index in run_graph.size() - 1:
		_connect_one_transition(run_graph[layer_index].nodes, run_graph[layer_index + 1].nodes)

func _connect_one_transition(current_layer: Array[RunNode], next_layer: Array[RunNode]) -> void:
	var targets := next_layer.duplicate()
	targets.shuffle()
	for target in targets:
		var candidates := current_layer.filter(func(n): return n.connections.size() < max_forward_edges)
		var source: RunNode = candidates.pick_random()
		source.connections.append(target)

	for source in current_layer:
		if source.connections.is_empty():
			source.connections.append(next_layer.pick_random())

	# Full-bipartite cap (2026-08-28, X-pattern pass) - a transition that
	# connects every source to every target always draws as a perfect X
	# (or denser fan) on the map, regardless of which two widths are
	# involved - the exact "every layer looks the same" symmetry problem
	# this pass fixes. Only pass three (below) can ever REACH full
	# connectivity: passes one/two above each contribute at most one edge
	# per target/per-zero-degree-source respectively, which is
	# mathematically short of the full current_layer.size() * next_layer.
	# size() total whenever current_layer has more than one node - so
	# capping HERE, without touching passes one/two at all, is sufficient
	# and can never violate their own reachability guarantees (this only
	# ever WITHHOLDS an edge pass three would otherwise have added, never
	# removes one passes one/two already placed).
	#
	# Exempt whenever current_layer.size() == 1 - a lone source MUST
	# already connect to every target (pass one had no other candidate to
	# assign any of them to), so "not fully bipartite" is structurally
	# impossible to ask for there; the cap would just silently do nothing
	# while making the code claim an intent it can't deliver on. This is
	# the "1-wide source forced to connect to everything" case named
	# directly in this pass's own brief.
	var full_bipartite_total := current_layer.size() * next_layer.size()
	var max_allowed_edges := full_bipartite_total - 1
	var chokepoint_source := current_layer.size() == 1

	for source in current_layer:
		while source.connections.size() < max_forward_edges and randf() < 0.5:
			if not chokepoint_source and _total_edges(current_layer) >= max_allowed_edges:
				break
			var available := next_layer.filter(func(n): return not source.connections.has(n))
			if available.is_empty():
				break
			source.connections.append(available.pick_random())

func _total_edges(layer: Array[RunNode]) -> int:
	var total := 0
	for node in layer:
		total += node.connections.size()
	return total

# Places the graph's guaranteed rooms - the final BOSS, this run's
# reserved ELITE layers (see _reserve_elite_layers() - done FIRST, so
# everything after it fills in around whatever got reserved), exactly one
# SHOP somewhere in shop_min_layer..shop_max_layer, one TREASURE, and
# (only while event_enabled is true - see its own doc, false by default
# as of 2026-09-07) one EVENT - then rolls everything left over COMBAT-
# weighted (see combat_weight/treasure_weight/event_weight above; ELITE was never part of that
# table, so nothing needs removing there - it was always assigned
# explicitly, first via the old node-pool slice, now via layer
# reservation).
#
# No longer ends in its own naming pass (2026-08-31, label-unification
# pass - REMOVED the per-run SUNKEN_WORKS_ROOM_NAMES/_pick_display_name()
# machinery this doc used to describe here, along with the trailing loop
# that called it). RunNode.display_name is left at its own "" default for
# every node now - map_screen.gd's _node_label() already falls back to
# the room's plain type label whenever display_name is empty, and that
# label now comes from RoomType.display_name(), the one place a room
# type's player-facing name lives. See RoomType.DISPLAY_NAMES's own doc.
func _assign_room_types() -> void:
	var boss_node: RunNode = run_graph[run_graph.size() - 1].nodes[0]
	boss_node.room_type = RoomType.Kind.BOSS

	# Layer 0 (the log's "Layer 1", the first generated layer right after
	# the opening room) is forced COMBAT the same way - see this pass's own
	# report for why this is the right precedent to follow: layer 0 is
	# ALWAYS exactly one node (_pick_layer_size() treats it as an endpoint,
	# same as the boss layer), so excluding it from `assignable`'s own
	# construction below (starting the loop at 1 instead of 0) protects it
	# from every downstream pass at once - elite, shop, treasure, event,
	# heap-min, and the leftover roll - without any of them needing their
	# own separate filter. _reserve_minimum_instances()'s own `n.layer != 0`
	# check becomes redundant after this (that candidate can never reach it
	# now), but is left in place - removing it is a separate concern.
	run_graph[0].nodes[0].room_type = RoomType.Kind.COMBAT

	var assignable: Array[RunNode] = []
	for layer_index in range(1, run_graph.size() - 1): # Excludes layer 0 (forced COMBAT above) and the boss's layer.
		assignable.append_array(run_graph[layer_index].nodes)

	var elite_result := _reserve_elite_layers(assignable)
	RunLogger.log_elite_layers(elite_result["layer_indices"], elite_result["side_by_side_layers"])

	# Filtered through `assignable` (unlike before this pass, when nothing
	# upstream could have already claimed a candidate) - elite reservation
	# above may have already taken a node out of this layer range, and
	# picking it again here would silently overwrite an ELITE with SHOP.
	var shop_candidates: Array[RunNode] = []
	for layer_index in range(shop_min_layer - 1, shop_max_layer): # -1: shop_min_layer is 1-indexed.
		for node in run_graph[layer_index].nodes:
			if assignable.has(node):
				shop_candidates.append(node)
	var shop_node: RunNode = shop_candidates.pick_random()
	shop_node.room_type = RoomType.Kind.SHOP
	assignable.erase(shop_node)

	var treasure_node: RunNode = assignable.pick_random()
	treasure_node.room_type = RoomType.Kind.TREASURE
	assignable.erase(treasure_node)

	# Gated on event_enabled (2026-09-07, EVENT-disable pass - see that
	# export's own doc) - false skips this guaranteed-one pick entirely,
	# leaving its node in `assignable` for the leftover roll below to
	# claim as COMBAT/TREASURE/HEAP/FORGE instead.
	if event_enabled:
		var event_node: RunNode = assignable.pick_random()
		event_node.room_type = RoomType.Kind.EVENT
		assignable.erase(event_node)

	# type_counts starts SEEDED from whatever _reserve_minimum_instances()
	# just guaranteed (see its own doc), not empty - a type's max cap
	# below has to account for a minimum that already placed one, or a
	# type seeded at min=1/max=2 could end up with 3 total (the guaranteed
	# one, uncounted, plus 2 more the leftover roll still thought were
	# free). SHOP/TREASURE/EVENT's own single guaranteed node above are ALSO
	# folded in here (2026-09-05, treasure-cap pass) - a cap on any of the
	# three would otherwise be inert: room_type_max_instances is checked
	# against type_counts below, and without this seeding a guaranteed pick
	# from the SHOP/TREASURE/EVENT passes above is invisible to that counter,
	# letting a "cap of 1" actually permit one guaranteed placement PLUS one
	# more from the leftover roll. Seeded unconditionally for SHOP/TREASURE
	# (not just whichever currently has a cap entry) so a future cap on
	# SHOP works correctly too, without this seeding step needing to be
	# revisited. EVENT's own seeding is gated on event_enabled (2026-09-07,
	# EVENT-disable pass) - seeding a count for a type that was never
	# actually placed this run would misrepresent type_counts for no
	# benefit, since event_weight is equally gated out of the weights dict
	# below when disabled.
	# Filtered before picking, not clamped after (same "exclude, don't
	# clamp" reasoning _pick_blob_count() above already uses for its own
	# cap) - a capped-out type has to lose ITS share of the roll's odds
	# entirely, not silently fold into whichever type happens to still be
	# open.
	var type_counts: Dictionary = _reserve_minimum_instances(assignable)
	type_counts[RoomType.Kind.SHOP] = type_counts.get(RoomType.Kind.SHOP, 0) + 1
	type_counts[RoomType.Kind.TREASURE] = type_counts.get(RoomType.Kind.TREASURE, 0) + 1
	if event_enabled:
		type_counts[RoomType.Kind.EVENT] = type_counts.get(RoomType.Kind.EVENT, 0) + 1
	for node in assignable:
		var weights: Dictionary = {
			RoomType.Kind.COMBAT: combat_weight,
			RoomType.Kind.TREASURE: treasure_weight,
			RoomType.Kind.HEAP: heap_weight,
			RoomType.Kind.FORGE: forge_weight,
		}
		# event_weight only enters the roll when event_enabled - false
		# means EVENT can never be picked below regardless of its weight
		# value, same gate as the guaranteed pick above (see event_
		# enabled's own doc).
		if event_enabled:
			weights[RoomType.Kind.EVENT] = event_weight
		var allowed: Dictionary = {}
		for kind in weights:
			var cap: int = room_type_max_instances.get(kind, -1)
			if cap < 0 or type_counts.get(kind, 0) < cap:
				allowed[kind] = weights[kind]
		var picked: RoomType.Kind = WeightedRandom.pick(allowed)
		node.room_type = picked
		type_counts[picked] = type_counts.get(picked, 0) + 1

# Reserves each RoomType.Kind's own room_type_min_instances count
# (2026-08-28, per-type minimum pass), chosen randomly among eligible/reachable
# candidates - called from _assign_room_types() right before the leftover
# weighted fill, so a guarantee is never left to the fill's own odds the
# way an ordinary roll would be. Returns a Dictionary of Kind -> count
# actually reserved, which the leftover fill loop seeds its own type_
# counts from (see that loop's own doc).
#
# Deliberately NOT built on _reserve_elite_layers() below (see this
# pass's own report) - that function's gap-spacing and side-by-side-
# promotion machinery exist specifically for ELITE's own min/max RANGE
# across MULTIPLE reserved layers; a flat per-type minimum count needs
# neither. What DOES generalize, and IS reused as-is here, is _compute_
# reachable_nodes() (already fully generic - no ELITE-specific logic in
# it at all) and the overall PATTERN elite's own reservation established
# (reserve first, among reachable candidates, before anything else fills
# in around it) - just without elite's own extra complexity this simpler
# guarantee doesn't need.
#
# Layer 0 (the run's own first non-opening room) is excluded from every
# reservation here, same reasoning elite_excluded_post_opening_layers
# already established for ELITE - NOT because layer 0 is currently
# guaranteed to be COMBAT (checked, not assumed, for this pass's own
# report: it ISN'T - EVENT/TREASURE/HEAP can already land there today via
# the ordinary guaranteed-random-pick/leftover-roll steps above, measured
# at roughly 40% of 200 generated runs combined), but because this new
# guarantee shouldn't be what makes that worse. A minimum reservation
# forces some type onto a layer with CERTAINTY, not just odds - layer 0
# is the one layer where adding new certainty of a non-combat room is
# least wanted, being the room reached immediately after the always-
# COMBAT opening room.
#
# min vs. max is NOT validated against each other here (no code added to
# reject or clamp a self-contradictory config) - if a future room_type_
# min_instances entry ever exceeded its own room_type_max_instances cap,
# the minimum would win unconditionally (this function runs, and commits
# its picks, before the leftover loop's own max-aware filtering ever
# executes), silently exceeding the stated maximum. Only a push_warning
# flags it; nothing prevents it. Not a real risk today (only HEAP: 1 is
# seeded, well under its own max of 2), but worth knowing before a second
# type's min/max are ever authored opposingly.
#
# Insufficient eligible rooms (more total minimums than the run actually
# has room for) is handled the same "reserve what's possible, warn, don't
# hang or crash" way _reserve_elite_layers()'s own max_feasible clamp and
# _place_content_positions()'s own fallback-plus-warning already handle
# their equivalent shortfalls.
func _reserve_minimum_instances(assignable: Array[RunNode]) -> Dictionary:
	var reached := _compute_reachable_nodes()
	var type_counts: Dictionary = {}
	for kind in room_type_min_instances:
		var needed: int = room_type_min_instances[kind]
		var cap: int = room_type_max_instances.get(kind, -1)
		if cap >= 0 and needed > cap:
			push_warning("RunState: room_type_min_instances[%s] (%d) exceeds room_type_max_instances[%s] (%d) - the minimum will win; the maximum will not actually hold this run." % [RoomType.Kind.keys()[kind], needed, RoomType.Kind.keys()[kind], cap])
		for i in needed:
			var candidates: Array = assignable.filter(func(n): return n.layer != 0)
			var reachable_candidates: Array = candidates.filter(func(n): return reached.has(n))
			var pool: Array = reachable_candidates if not reachable_candidates.is_empty() else candidates
			if pool.is_empty():
				push_warning("RunState: not enough eligible rooms left to guarantee %s - only %d of its own %d minimum reserved." % [RoomType.Kind.keys()[kind], i, needed])
				break
			var chosen: RunNode = pool.pick_random()
			chosen.room_type = kind
			assignable.erase(chosen)
			type_counts[kind] = type_counts.get(kind, 0) + 1
	return type_counts

# Reserves this run's guaranteed elite LAYERS (see elite_layer_count_min/
# _max's own doc for why this replaced the old node-pool approach) -
# called first from _assign_room_types() above, before SHOP/TREASURE/
# EVENT are placed, so the rest of that function just fills in around
# whatever this already claimed (each reserved node is removed from
# `assignable` in place, the same "caller's array, mutated as we go"
# convention every other step in _assign_room_types() already uses).
# Returns the chosen layer indices and which of them got a side-by-side
# promotion, purely for RunLogger.log_elite_layers() to report - nothing
# in this function reads its own return value back.
func _reserve_elite_layers(assignable: Array[RunNode]) -> Dictionary:
	var eligible_layers: Array[int] = []
	for layer_index in range(elite_excluded_post_opening_layers, run_graph.size() - 1): # -1: excludes the boss layer.
		eligible_layers.append(layer_index)

	var gap: int = maxi(elite_layer_min_gap, 1)
	var target_count: int = randi_range(elite_layer_count_min, elite_layer_count_max)
	if eligible_layers.is_empty():
		target_count = 0
	else:
		# Largest k such that k layers, pairwise at least `gap` apart, fit
		# inside eligible_layers.size() slots - clamps a T the algorithm
		# can't actually deliver (a short custom layer_count, or a wide
		# gap) down to what's real, rather than _select_elite_layers()
		# below silently under- or over-shooting it.
		var max_feasible: int = 1 + (eligible_layers.size() - 1) / gap
		target_count = min(target_count, max_feasible)

	var elite_layer_indices := _select_elite_layers(eligible_layers, target_count, gap)

	# Reachable-from-entry check. Computed once, up front, off the edges
	# _connect_layers() already finalized before _assign_room_types() ever
	# runs. Every candidate node is filtered down to this set BEFORE
	# picking, rather than picking blind and rerouting after the fact -
	# functionally identical to "move the elite to a reachable node in the
	# same layer" whenever a reachable node exists there, just without a
	# separate detect-then-fix step.
	#
	# In THIS generator a layer with zero reachable nodes can't actually
	# happen: _connect_layers()'s own three-pass guarantee (see its doc)
	# makes every node in every layer reachable from the start, by
	# induction from layer 0 forward - confirmed by _validate_run_graph()'s
	# own separate unreachable-check, which this pass leaves completely
	# untouched. The filter below is kept anyway, as the defensive floor
	# this was explicitly asked for, in case a future change to _connect_
	# layers() ever weakens that guarantee without this file being updated
	# to match.
	var reached := _compute_reachable_nodes()

	var side_by_side_layers: Array[int] = []
	for layer_index in elite_layer_indices:
		var layer_nodes := run_graph[layer_index].nodes
		var reachable_nodes := layer_nodes.filter(func(n): return reached.has(n))
		var candidates: Array = reachable_nodes if not reachable_nodes.is_empty() else layer_nodes
		var elite_node: RunNode = candidates.pick_random()
		elite_node.room_type = RoomType.Kind.ELITE
		assignable.erase(elite_node)

		# Side-by-side promotion (see elite_side_by_side_promotion_chance's
		# own doc) - only possible in a layer with a second node to
		# promote; still counts as one entry in elite_layer_indices either
		# way, since the count this function reports is layers, not nodes.
		if layer_nodes.size() > 1 and randf() < elite_side_by_side_promotion_chance:
			var remaining := layer_nodes.filter(func(n): return n != elite_node)
			var reachable_remaining := remaining.filter(func(n): return reached.has(n))
			var second_candidates: Array = reachable_remaining if not reachable_remaining.is_empty() else remaining
			var second_elite: RunNode = second_candidates.pick_random()
			second_elite.room_type = RoomType.Kind.ELITE
			assignable.erase(second_elite)
			side_by_side_layers.append(layer_index)

	return {"layer_indices": elite_layer_indices, "side_by_side_layers": side_by_side_layers}

# Picks `target_count` entries out of `eligible_layers` (already sorted
# ascending, always a contiguous run of layer indices - see this
# function's only caller) such that any two chosen layers are at least
# `gap` apart. Built via an index-compression trick rather than shuffle-
# and-reject: draw a WITHOUT-replacement sample from a range shrunk by
# (target_count - 1) * (gap - 1) slots, sort it, then expand each picked
# index back out by (gap - 1) times its own rank among the picks. This
# can never fail to find a valid arrangement or need a retry loop, unlike
# picking randomly and rejecting anything that violates the gap.
# target_count is assumed already clamped to what eligible_layers/gap can
# actually support (see _reserve_elite_layers() above) - this trusts
# that, the same "caller already checked" stance the rest of this file
# takes (e.g. spend_gold()'s own doc).
func _select_elite_layers(eligible_layers: Array[int], target_count: int, gap: int) -> Array[int]:
	if target_count <= 0:
		return []
	var reduced_size: int = eligible_layers.size() - (target_count - 1) * (gap - 1)
	var reduced_pool: Array[int] = []
	for i in reduced_size:
		reduced_pool.append(i)
	reduced_pool.shuffle()
	var picked: Array[int] = reduced_pool.slice(0, target_count)
	picked.sort()

	var chosen: Array[int] = []
	for i in target_count:
		chosen.append(eligible_layers[picked[i] + i * (gap - 1)])
	return chosen

# Same single-forward-pass reachability computation _validate_run_graph()
# already does at the very end of generation (see its own `reached`
# dictionary) - duplicated here in miniature rather than shared, because
# this needs to run mid-generation, inside _assign_room_types(), well
# before _validate_run_graph() itself ever runs. Layer 0's sole node is
# seeded reached directly (nothing in run_graph points to it - it's only
# ever reached via the separately-prepended opening_node's own single
# connection, which isn't part of this graph at all) - every other
# layer's reachability then falls out of one pass over every node's own
# connections, since _connect_layers() guarantees a node only ever
# receives edges FROM an already-reached predecessor layer (built
# strictly layer-by-layer, forward only - see its own doc).
func _compute_reachable_nodes() -> Dictionary:
	var reached: Dictionary = {}
	reached[run_graph[0].nodes[0]] = true
	for layer in run_graph:
		for node in layer.nodes:
			for target in node.connections:
				reached[target] = true
	return reached

# Dev aid (see DESIGN.md's Run Structure & Navigation): prints the whole
# graph, layer by layer, so generation can be eyeballed for correctness
# without a map screen - not something the player ever sees. Prints
# opening_node first, on its own "Layer 0 (Opening)" line, ahead of the
# untouched layer loop below - it's not one of run_graph's own elements,
# so it can't fall out of that loop for free.
func _print_run_graph() -> void:
	var text := _run_graph_text()
	print(text)
	RunLogger.log_run_graph(text)

func _run_graph_text() -> String:
	var lines: Array[String] = ["Run graph:", "  Layer 0 (Opening):"]
	lines.append("    %s [%s]%s" % [opening_node.id, _type_name(opening_node.room_type), _connections_text(opening_node)])
	for layer_index in run_graph.size():
		lines.append("  Layer %d:" % (layer_index + 1))
		for node in run_graph[layer_index].nodes:
			lines.append("    %s [%s]%s" % [node.id, _type_name(node.room_type), _connections_text(node)])
	return "\n".join(lines)

func _type_name(room_type: RoomType.Kind) -> String:
	match room_type:
		RoomType.Kind.COMBAT:
			return "COMBAT"
		RoomType.Kind.TREASURE:
			return "TREASURE"
		RoomType.Kind.EVENT:
			return "EVENT"
		RoomType.Kind.SHOP:
			return "SHOP"
		RoomType.Kind.ELITE:
			return "ELITE"
		RoomType.Kind.BOSS:
			return "BOSS"
		RoomType.Kind.HEAP:
			return "HEAP"
		RoomType.Kind.FORGE:
			return "FORGE"
		_:
			return "?"

func _connections_text(node: RunNode) -> String:
	if node.connections.is_empty():
		return ""
	var text := " -> "
	for i in node.connections.size():
		if i > 0:
			text += ", "
		text += node.connections[i].id
	return text

# Dev aid: re-checks every invariant the generator above is SUPPOSED to
# guarantee (edge caps, reachability, exactly one shop, a terminal boss)
# and reports anything that doesn't hold, rather than trusting the
# generator got it right. The point is that a future bug in
# _connect_layers()/_assign_room_types() announces itself here, loudly,
# at run start - instead of surfacing later as a crash or a silently
# unreachable room somewhere mid-run (see the max_forward_edges bug this
# was written after).
func _validate_run_graph() -> void:
	var violations: Array[String] = []
	var reached: Dictionary = {} # RunNode -> true, for every node with an incoming edge.
	var shop_count := 0
	var elite_layers: Dictionary = {} # layer_index (0-indexed) -> true, for every layer holding at least one ELITE node.

	for layer_index in run_graph.size():
		var is_final_layer := layer_index == run_graph.size() - 1
		for node in run_graph[layer_index].nodes:
			if node.room_type == RoomType.Kind.SHOP:
				shop_count += 1
			if node.room_type == RoomType.Kind.ELITE:
				elite_layers[layer_index] = true
				var excluded_by_opening := layer_index < elite_excluded_post_opening_layers
				var excluded_by_boss := layer_index > run_graph.size() - 2
				if excluded_by_opening or excluded_by_boss:
					violations.append("%s is ELITE at layer %d - inside the excluded opening/boss window." % [node.id, layer_index + 1])

			var out_degree := node.connections.size()
			if is_final_layer:
				if out_degree != 0:
					violations.append("%s is in the final layer but has %d forward edge(s) - should be terminal." % [node.id, out_degree])
			elif out_degree < 1 or out_degree > max_forward_edges:
				violations.append("%s has %d forward edge(s) - expected 1-%d." % [node.id, out_degree, max_forward_edges])

			for target in node.connections:
				reached[target] = true
				if target.layer != node.layer + 1:
					violations.append("%s connects to %s, which isn't in the very next layer." % [node.id, target.id])

	for layer_index in range(1, run_graph.size()): # Skip layer 0: the start has no predecessor.
		for node in run_graph[layer_index].nodes:
			if not reached.has(node):
				violations.append("%s is unreachable - nothing connects to it." % node.id)

	if shop_count != 1:
		violations.append("Expected exactly 1 SHOP node, found %d." % shop_count)

	var elite_layer_count := elite_layers.size()
	if elite_layer_count < elite_layer_count_min or elite_layer_count > elite_layer_count_max:
		violations.append("Expected %d-%d ELITE layer(s), found %d." % [elite_layer_count_min, elite_layer_count_max, elite_layer_count])

	var sorted_elite_layers: Array = elite_layers.keys()
	sorted_elite_layers.sort()
	for i in range(1, sorted_elite_layers.size()):
		var prev_layer: int = sorted_elite_layers[i - 1]
		var this_layer: int = sorted_elite_layers[i]
		if this_layer - prev_layer < elite_layer_min_gap:
			violations.append("ELITE layers %d and %d are only %d apart - expected at least %d." % [prev_layer + 1, this_layer + 1, this_layer - prev_layer, elite_layer_min_gap])

	var boss_node: RunNode = run_graph[run_graph.size() - 1].nodes[0]
	if boss_node.room_type != RoomType.Kind.BOSS:
		violations.append("Final node %s is type %s, not BOSS." % [boss_node.id, _type_name(boss_node.room_type)])

	# opening_node isn't part of run_graph (see its own comment), so
	# nothing above ever visits it - checked separately here instead of
	# folding it into the layer loop.
	if opening_node.room_type != RoomType.Kind.COMBAT:
		violations.append("Opening node %s is type %s, not COMBAT." % [opening_node.id, _type_name(opening_node.room_type)])
	if opening_node.connections != [run_graph[0].nodes[0]]:
		violations.append("Opening node %s should connect to exactly %s, connects to %s instead." % [opening_node.id, run_graph[0].nodes[0].id, _connections_text(opening_node)])

	if violations.is_empty():
		print("Run graph validated: OK.")
		return
	push_error("Run graph validation failed (%d issue(s)):" % violations.size())
	for violation in violations:
		push_error("  " + violation)

# Autoloads get their own _ready() just like any node, called before the
# game's first scene - so this is where "a fresh run" gets built the very
# first time, by calling the exact same reset() used for New Run. That
# way there's only one definition of what a fresh run looks like, not one
# in a var initializer and a second, hopefully-matching one in reset().
#
# randomize() seeds the engine's global RNG from OS entropy - without it,
# every randi()/randf()/pick_random() call anywhere in the project (the
# run graph's shape, EnemyPool's weighted pick, card/gold rolls, ...) is
# deterministic: the exact same sequence every time the game process
# starts fresh, since GDScript's default seed is fixed. RunState is the
# FIRST autoload (see project.godot's [autoload] order), so calling this
# here, before reset() consumes any randomness, guarantees it happens
# exactly once per process and before anything else could roll first.
func _ready() -> void:
	randomize()
	reset()

# Called after winning a battle, moving on to the next one: HP, gold, and
# deck all carry over exactly as they were (no healing between fights, on
# purpose - see DESIGN.md), only the battle count advances.
func advance_to_next_battle() -> void:
	battle_number += 1

# Called when the exit door in a field room is used (see field_exit.gd).
# A coarser counter than battle_number: a room can (and usually does)
# contain several battles before its exit is reached.
func advance_to_next_room() -> void:
	room_number += 1

# The one place gold actually changes - field_chest.gd and
# reward_screen.gd both call this instead of touching `gold` directly, so
# gold_changed above is always accurate for whatever's listening.
func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

# The mirror of add_gold() above, for the SHOP's purchases - shop_window.gd
# calls this instead of touching `gold` directly, for the same reason:
# gold_changed needs to fire every time the number actually changes, not
# just when it goes up. Callers are expected to have already checked
# affordability (every shop row disables its own Buy button once the
# price exceeds current gold) - this doesn't clamp at 0, the same "trust
# the call site checked" stance add_gold() already takes on its own input.
func spend_gold(amount: int) -> void:
	gold -= amount
	gold_changed.emit(gold)

# The shard mirror of add_gold()/spend_gold() above (2026-09-02, forge
# pass) - same shape, same reasoning: whatever grants/spends shards calls
# these instead of touching `shards` directly, so shards_changed stays
# accurate for anything that ever listens to it. No real caller grants
# shards yet (see `shards`'s own doc) - add_shards() exists ahead of that
# so a dev tool (or a future pickup) has something to call.
func add_shards(amount: int) -> void:
	shards += amount
	shards_changed.emit(shards)

# spend_shards() doesn't clamp at 0 either, same "trust the call site
# checked" stance spend_gold() takes - field_forge.gd only ever calls this
# after CardUpgradeService.offer_upgrade() reports UPGRADED, which itself
# only runs after the forge's own prompt gated on shards > 0.
func spend_shards(amount: int) -> void:
	shards -= amount
	shards_changed.emit(shards)

# --- player_hp mutators (2026-09-05, HP-signal pass) ---
#
# Three functions, not one with a floor parameter or a kind enum - named
# for the three real clamp reasons found across every existing player_hp
# write site (battle.gd, field_heap.gd, pay_window.gd, sift_outcome_
# resolver.gd, shop_window.gd), rather than one shared shape that would
# force every non-combat caller to keep passing the same literal 1. All
# three take a DELTA (matching every one of those call sites, which
# already compute `player_hp - amount`/`player_hp + amount` inline) -
# battle.gd's own _set_player_hp() is the one exception (it takes an
# already-computed FINAL value, for its own Toll-accrual reasons), so it
# converts to a delta internally rather than this shape changing to fit
# it - see that function's own doc.

# Combat only - 0 is a real, reachable state (triggers defeat). battle.gd's
# own _set_player_hp() is the only intended caller; it still owns Toll
# accrual/_took_damage_this_turn/hand-affordability on top of this.
func take_damage(amount: int) -> void:
	player_hp = clampi(player_hp - amount, 0, player_max_hp)
	player_hp_changed.emit(player_hp, player_max_hp)

# Every non-combat HP cost (a heap sift, a pay-house blood cost, a hazard-
# flavored heap/curio outcome) - floored at 1, never fatal, same "no
# field-side death handling anywhere in this project" reasoning every one
# of those call sites already documented independently before this pass.
func lose_hp(amount: int) -> void:
	player_hp = clampi(player_hp - amount, 1, player_max_hp)
	player_hp_changed.emit(player_hp, player_max_hp)

# Every non-combat heal (Rest, a beneficial heap/curio HP_CHANGE) - ceiling
# only, no floor needed since this only ever adds.
func heal(amount: int) -> void:
	player_hp = mini(player_hp + amount, player_max_hp)
	player_hp_changed.emit(player_hp, player_max_hp)

# Not speculative - player_max_hp WILL change mid-run (a future item/
# upgrade), unlike the rest of this file's own run-start-only fields.
# Clamps player_hp down if the new ceiling is now below it (losing max HP
# below current HP has to take current HP with it, the same way a
# shrinking bar couldn't otherwise render), but deliberately does NOT
# raise player_hp when the ceiling rises - gaining max HP is gaining
# ceiling, not free healing, same distinction a real max-HP-up effect in
# any HP-bar game makes. player_hp_changed only fires when player_hp
# itself actually moved (the clamp-down case) - player_max_hp_changed
# fires unconditionally, since the ceiling always changes when this is
# called.
func set_max_hp(new_max: int) -> void:
	player_max_hp = new_max
	if player_hp > player_max_hp:
		player_hp = player_max_hp
		player_hp_changed.emit(player_hp, player_max_hp)
	player_max_hp_changed.emit(player_max_hp)

# Called to start a brand new run from scratch, after a defeat.
func reset() -> void:
	current_class = WANDERER
	current_biome = SUNKEN_WORKS
	player_max_hp = DEFAULT_PLAYER_MAX_HP
	player_hp = player_max_hp
	battle_number = 1
	room_number = 1
	gold = 0
	shards = 0
	first_combat_generated = false
	equipped_weapon = null
	equipped_trinket = null
	npc_interacted = {}
	opening_room_hull_line_shown = false
	event_content_generated = {}
	sift_outcomes_drawn = []
	card_removals_purchased = 0
	deck = _build_starting_deck()
	RunLogger.start_run()
	_generate_run_graph()

func _build_starting_deck() -> Array[CardData]:
	var fresh_deck: Array[CardData] = []
	for card: CardData in STARTING_DECK:
		for i in STARTING_DECK[card]:
			# .duplicate() - per-copy identity pass (2026-08-29, see add_card_
			# to_deck()'s own doc below for the full reasoning; this loop
			# doesn't go through that function, so it needs the exact same
			# call here). STARTING_DECK's own keys are already-loaded CardData
			# resources (Dictionary keys, shared across every entry that maps
			# to the same key) - without this, 5x Slash would still append
			# the SAME object 5 times, exactly the bug this pass fixes.
			fresh_deck.append(card.duplicate())
	return fresh_deck

# Called when the player picks a card reward, buys from a shop, accepts
# an NPC offer, or resolves a sift outcome that grants a card - adds it
# to the run's deck permanently, from the next battle onward. The ONE
# chokepoint every one of those grant paths already funnels through
# (reward_screen.gd, shop_window.gd, field_room.gd's NPC offer, sift_
# outcome_resolver.gd - none of them append to `deck` directly).
#
# .duplicate() here is LOAD-BEARING (2026-08-29, per-copy card identity
# pass), not defensive belt-and-suspenders: `card_data` is whatever the
# caller already has in hand, which for every real caller is a CardPool.
# load_class_pool()-sourced resource - and Godot's load() caches by path,
# so every reward roll, shop slot, and NPC offer that names the same
# card (e.g. "Slash") for the same run hands this the EXACT SAME engine-
# cached object, not merely an equal one. Appending that reference
# directly, un-duplicated, would silently reintroduce the exact bug this
# pass exists to fix: every "Slash" ever granted this run would still be
# ONE shared CardData instance, indistinguishable by object identity no
# matter how many separate grant events added one - the underlying cause
# is identical to _build_starting_deck()'s own STARTING_DECK dictionary
# keys just above, not a separate problem.
#
# SHALLOW duplicate (Resource.duplicate()'s own default, subresources=
# false) - deliberately NOT duplicate(true). CardData's own Resource-
# typed fields (effects: Array[CardEffect], chain_followup_effect,
# upgrades: Array[CardData]) stay shared references to the same
# authored objects across every duplicated copy. That's correct, not an
# oversight: nothing in this codebase ever mutates a CardEffect (or a
# StatusEffectData an effect points at) once loaded - confirmed by
# checking every direct field WRITE onto a CardEffect in the project;
# the only one found (battle.gd's own _chain_payoff_effect) builds and
# configures a throwaway CardEffect.new() Battle owns privately, never
# one read off a card's own `effects` array. A deep duplicate here would
# only multiply memory for data that's already safely shareable (every
# copy of "Slash" reading the exact same immutable Damage-6 CardEffect
# is fine, precisely because none of them can ever write to it) - and
# for `upgrades` specifically, it would additionally fragment "Slash
# Plus" into N distinct-but-value-identical per-slot duplicate objects
# for no benefit, since upgrade CANDIDATES are read-only menu options
# too, never mutated before (or after) being chosen. The failure mode
# per-copy identity actually needs to prevent is mutable state leaking
# between copies - shallow duplicate already closes that for CardData's
# OWN fields (energy_cost, removal_scope, etc.), and going one level
# deeper into effects/upgrades would be defending against a mutation
# that structurally cannot happen today.
func add_card_to_deck(card_data: CardData) -> void:
	deck.append(card_data.duplicate())

# Called when a CONSUMED card (see card_data.gd's `removal_scope` field)
# gets played - a one-time-use card leaves the run's deck for good the
# moment it's played, not just the current fight. Array.erase() removes
# only the FIRST matching element - since every deck slot is now its own
# distinct CardData instance (2026-08-29, per-copy card identity pass -
# see add_card_to_deck()'s own doc), `card_data` here is the EXACT
# object the player actually played (battle.gd's _play_card() passes the
# clicked hand card's own reference straight through), so this now
# correctly removes THAT SPECIFIC copy - not "a" same-named slot that
# happened to match first, which is all identity-erase could ever
# guarantee back when every same-named copy shared one object.
func remove_card_from_deck(card_data: CardData) -> void:
	deck.erase(card_data)

# Called by card_upgrade_service.gd once a card and its upgrade have
# both been chosen - swaps the matching entry in place. Now correctly
# targets the SPECIFIC copy the player clicked in Belongings (2026-08-29,
# per-copy card identity pass), not just whichever same-named slot
# happened to be first: DeckViewer's card_selected signal always carried
# the exact CardData reference the clicked Card instance held, but with
# every same-named copy sharing one object, "which slot" and "which
# reference" used to be the same question with only one possible answer.
# They're no longer the same question - deck.find(old_card) now resolves
# to the one slot that's actually THAT object, because every slot holds
# its own. find(), not erase()+append(): a plain index write, and it
# fails silently (a no-op) if `old_card` somehow isn't in the deck any
# more rather than corrupting deck order - the caller already re-checked
# eligibility against the live deck immediately before this is ever
# called, so that should never actually happen, but this doesn't need to
# trust that.
#
# new_card.duplicate() (2026-08-31, per-copy-identity-on-upgrade fix) -
# THIS was the one deck-mutating path in this file that didn't duplicate,
# unlike _build_starting_deck() and add_card_to_deck() above. `new_card`
# is `chosen.upgrades[0]` (or whichever entry the player picked) straight
# off the base CardData's own `upgrades` array - the same loaded Resource
# object every time, since Godot's resource loader caches by path. Two
# separate slots upgrading to the same card (both of the deck's 5 Slashes
# going to Slash+, say) would otherwise end up holding the LITERAL SAME
# object in two different deck indices - exactly the bug the whole per-
# copy-identity pass was built to prevent, just reopened at the one
# mutation site that predates that pass's own upgrade feature.
func replace_card_in_deck(old_card: CardData, new_card: CardData) -> void:
	var index := deck.find(old_card)
	if index != -1:
		deck[index] = new_card.duplicate()
