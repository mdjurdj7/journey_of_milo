extends Node
# Another autoload (see run_state.gd for the fuller explanation of what
# that means) - a DEV TOOL, not a shipping feature: writes a plain-text
# summary of one run (the generated graph, every room/battle/reward
# choice, turn-by-turn combat) to a timestamped file under run_logs/, so
# a run can be read back afterward instead of reconstructed from memory
# or console scrollback. See DESIGN.md's own note on this for how to
# read the output and what it's for.
#
# Every hook elsewhere just calls one of the log_*()/begin_*()/end_*()
# functions below at the moment that thing already happens - this file
# never reaches INTO battle.gd/reward_screen.gd/map_screen.gd to ask
# what occurred, they tell it. Same "one place owns the how" split
# AudioManager/MusicManager already use for their own concern.

@export var enabled: bool = true
# The toggle - flip to false (in run_logger.tscn's own Inspector, same
# place every other autoload's tuning knobs live) to turn this off
# entirely with no other code changes. Every public function below
# checks this first and no-ops immediately when false, so disabling it
# has zero cost beyond that one check - nothing upstream needs to know
# or care whether logging is currently on.

const LOG_FOLDER := "res://run_logs/"

var _lines: Array[String] = []

# --- Per-battle accumulator (see log_battle_start()/log_battle_end()) ---
#
# Same shape as the per-turn accumulator below (reset at the natural
# "this thing is starting" hook, accumulated via the existing log_*()
# calls each event already goes through, flushed as one summary line at
# the end) - a second instance of that pattern, not a parallel one. Reset
# in log_battle_start() specifically (called once per battle.gd's own
# _start_battle(), NOT on scene load/autoload _ready()) so a run spanning
# several battles gets an independent count for each one.
var _battle_hp_start: int = 0
var _battle_damage_dealt: int = 0
var _battle_damage_taken: int = 0
var _battle_damage_blocked: int = 0
var _battle_absorb_used: int = 0
# Absorb's own counterpart to _battle_damage_blocked above (2026-09-05,
# Forbearance pass) - same shape, same reset point (log_battle_start()),
# same "accumulated via the one call site that actually spends it"
# pattern. See log_absorb_used() below for the one difference from
# block's own logger: absorb is fight-persistent, not turn-cleared, but
# that distinction lives in battle.gd's own absorb_pool, not here - this
# just counts how much of it got spent, exactly like block.
var _battle_toll_accrued: int = 0
var _battle_toll_peak: int = 0
var _last_toll: int = 0
# Per-source split of _battle_toll_accrued above (2026-09-02, Toll source
# tracking pass) - same total, broken down by which of the three
# originating HP-loss paths caused each accrued delta (see TollSource's
# own doc, below log_toll_change()). Always sums to _battle_toll_accrued
# exactly, since both are incremented by the same `delta` in the same
# `if delta > 0` branch of log_toll_change() - two views of one number,
# not two independently-tracked totals that could drift apart.
var _battle_toll_accrued_enemy: int = 0
var _battle_toll_accrued_self: int = 0
var _battle_toll_accrued_status: int = 0
# Owed counters (2026-09-08, Owed status pass) - same three-related-
# counters-together shape as the Toll-by-source trio just above, not the
# single-counter shape _battle_absorb_used uses, since these three are
# meant to be read as one story (how much was granted, how much actually
# paid off, how much was wasted by killing the holder before it could).
var _battle_owed_applied: int = 0
var _battle_owed_collected: int = 0
var _battle_owed_lost_on_death: int = 0
# Not reset to RunState's own current toll - toll is always 0 at battle
# start (battle.gd's own _start_battle() resets it before this reads
# anything), and log_toll_change() below only ever needs to know the
# PREVIOUS value it was told, to turn "the new value" into "how much this
# specific change added," so 0 is always the correct starting point.
var _battle_cards_played: int = 0
var _battle_energy_unspent_total: int = 0
var _battle_openers_played: int = 0
var _battle_chain_payoffs_fired: int = 0
var _battle_chain_expired: int = 0
var _battle_enemy_names: Array[String] = []
# BOSS_01's own Charge mechanic (2026-08-29, BOSS_01 pass - see battle.
# gd's _advance_boss_charge()) - "this is the data that tells us whether
# the threshold is tuned," this feature's own brief. Zero/empty for every
# fight that never involves a Charge-boss, same "only meaningful for the
# one mechanic that populates it" shape every other per-battle
# accumulator here already has for a mechanic that isn't in EVERY fight
# (chain openers/payoffs, say). accumulated damage is recorded at every
# CHECK, interrupted or not - the tuning signal isn't just the pass/fail
# count, it's how CLOSE each check actually was to the threshold.
var _battle_boss_charges_attempted: int = 0
var _battle_boss_charges_interrupted: int = 0
var _battle_boss_charges_buffed: int = 0
var _battle_boss_charge_check_damages: Array[int] = []

# GUN/SUPPLY - the Sunken Works' first two-entity encounter-linked-damage
# fight (2026-08-29, see enemy_data.gd's own "Encounter-linked damage"
# section) - same "zero/empty for every fight that doesn't involve this
# mechanic" shape the Boss Charge fields just above already use.
#
# WHAT THIS IS ACTUALLY FOR: the design's own open question, not settled
# by tuning alone - at SUPPLY 35hp/GUN 70hp/base 12/steps 12-6-4/fallback
# 3, clearing SUPPLY is EXPECTED to be somewhat favored (see this
# encounter's own design report: ~35% less total damage taken for ~57%
# more turns exposed) - but "somewhat favored" is only a real fork if
# real playtests sometimes go the other way. If _battle_damage_source_
# died_turn is -1 (SUPPLY ignored) in a meaningful fraction of logged
# fights, the fork is real. If it is NEVER -1 across a real sample, the
# fork isn't real at these numbers - the fix from there is raising
# SUPPLY's own hp or damage_source_dead_value (the fallback), not
# reworking the mechanic.
var _battle_damage_source_died_turn: int = -1
# -1 means "never died this fight" (ignored entirely, or the fight ended
# before finishing it off) - a real turn number (1-indexed, matching
# _turn_number elsewhere) means the turn _on_enemy_defeated() fired for
# whichever enemy some OTHER enemy in the fight was reading via damage_
# source_enemy. Generic over which enemy that is - not hardcoded to
# "SUPPLY" by name, in case a second encounter ever reuses this mechanic.
var _battle_linked_attack_steps: Array[int] = []

# --- Per-battle CSV sidecar (2026-09-02, Toll source tracking pass) ---
#
# One row per battle, written alongside the existing run_TIMESTAMP.txt
# (same run, same timestamp - see _write_to_file()) as run_TIMESTAMP.csv,
# for pulling per-battle Toll-source numbers into a spreadsheet across
# many runs without parsing the free-text log. Columns are additive by
# convention - the existing ones never change shape, anything new gets
# appended at the end - so a script written against today's header
# still reads correctly once a later pass adds another column.
const CSV_HEADER := "battle,enemies,turns,hp_start,hp_end,damage_dealt,damage_taken,damage_blocked,toll_accrued,toll_peak,toll_enemy,toll_self,toll_status,absorb_used,owed_applied,owed_collected,owed_lost_on_death"
# absorb_used appended at the END (2026-09-05, Forbearance pass) - per this
# const's own header comment, existing columns never change shape or
# position, so a script written against an earlier header still reads
# correctly. owed_applied/owed_collected/owed_lost_on_death appended the
# same way (2026-09-08, Owed status pass).
var _csv_rows: Array[String] = []
var _battle_index: int = 0
# One entry per ATTACK an encounter-linked enemy (GUN) actually lands,
# in order - the REAL damage value, not an abstract step index, so the
# printed log line is self-explanatory without a legend (12/6/4 already
# ARE the authored bracket values; 3 appearing after the death turn
# above confirms the fallback engaged, not a fourth bracket).

# --- Per-turn accumulator (see begin_turn()/end_turn()) ---
var _turn_active: bool = false
var _turn_number: int = 0
var _turn_hp_before: int = 0
var _turn_damage_dealt: int = 0
var _turn_damage_taken: int = 0
var _turn_cards_played: Array[String] = []

# --- Run ---

func start_run() -> void:
	if not enabled:
		return
	_lines.clear()
	_turn_active = false
	_csv_rows = [CSV_HEADER]
	_battle_index = 0
	_lines.append("=== RUN START ===")
	_lines.append("Class: %s" % RunState.current_class.character_name)
	_lines.append(_deck_summary_line("Starting deck", RunState.deck))
	_lines.append("")

# Called from run_state.gd's _print_run_graph() with the exact same text
# it already prints to the console - one formatter, two destinations,
# not a second copy of the graph-printing logic here.
func log_run_graph(graph_text: String) -> void:
	if not enabled:
		return
	_lines.append(graph_text)
	_lines.append("")

# Called from run_state.gd's _assign_room_types(), right after elite
# layers are reserved (see that function's own _reserve_elite_layers()
# doc) - a compact, structured summary, separate from the full graph dump
# log_run_graph() above already writes, specifically so the 2-4-elite-
# layers guarantee (and the min-gap/no-side-by-side-bunching rules that
# go with it) can be checked by grepping many runs' logs at once, rather
# than eyeballing every [ELITE] tag inside each run's own full printout.
func log_elite_layers(layer_indices: Array[int], side_by_side_layers: Array[int]) -> void:
	if not enabled:
		return
	var layer_display: Array[String] = []
	for layer_index in layer_indices:
		layer_display.append(str(layer_index + 1)) # 1-indexed, matches every other layer reference in this log.
	var promotion_display: Array[String] = []
	for layer_index in side_by_side_layers:
		promotion_display.append(str(layer_index + 1))
	var promotion_text := "none" if promotion_display.is_empty() else ", ".join(promotion_display)
	_lines.append("Elite layers: %d chosen (%s) | side-by-side promotions: %s" % [layer_indices.size(), ", ".join(layer_display), promotion_text])
	_lines.append("")

func end_run(victory: bool) -> void:
	if not enabled:
		return
	_lines.append("=== RUN END: %s ===" % ("VICTORY" if victory else "DEFEAT"))
	_lines.append("Rooms reached: %d" % RunState.room_number)
	_lines.append("Final HP: %d/%d" % [RunState.player_hp, RunState.player_max_hp])
	_lines.append("Final gold: %d" % RunState.gold)
	_lines.append("Final shards: %d" % RunState.shards)
	_lines.append(_deck_summary_line("Final deck", RunState.deck))
	_write_to_file()

# --- Rooms ---

# previous_node is whichever RunNode the player was AT (its own
# .connections are every option that was actually on the table) -
# called before RunState.current_node gets reassigned to the chosen
# one, so this is the one place both "what was chosen" and "what else
# was available" are simultaneously known.
func log_room_entered(previous_node: RunNode, chosen_node: RunNode) -> void:
	if not enabled:
		return
	var alternatives: Array[String] = []
	for node in previous_node.connections:
		var marker := " (chosen)" if node == chosen_node else ""
		alternatives.append("%s [%s]%s" % [node.id, RoomType.Kind.keys()[node.room_type], marker])
	_lines.append("--- Room: %s [%s] ---" % [chosen_node.id, RoomType.Kind.keys()[chosen_node.room_type]])
	if alternatives.size() > 1:
		_lines.append("  Options were: %s" % ", ".join(alternatives))

# The opening room never goes through log_room_entered() above - it's
# entered directly from the title screen (see title_screen.gd's
# _on_begin_run_pressed()), never chosen off the map, so there's no
# "previous node"/"alternatives" to report, just the room itself.
func log_opening_room(node: RunNode) -> void:
	if not enabled:
		return
	_lines.append("--- Room: %s [%s] (Opening) ---" % [node.id, RoomType.Kind.keys()[node.room_type]])

func log_gold_gained(amount: int, source: String) -> void:
	if not enabled:
		return
	_lines.append("  Gold gained: %d (%s)" % [amount, source])

# Shard mirror of log_gold_gained() above (2026-09-02, forge pass) - same
# shape, same "kind is a short label, not an enum" reasoning. Unlike gold,
# the SPEND side gets its own logger too (log_shard_spent() below) - gold
# spends aren't logged anywhere today (shop purchases only ever show up
# indirectly, via the final gold total), but a forge visit is rare enough
# per run that seeing exactly when/where a shard went is worth a line of
# its own, not just inferable from the before/after totals.
func log_shard_gained(amount: int, source: String) -> void:
	if not enabled:
		return
	_lines.append("  Shard gained: %d (%s)" % [amount, source])

func log_shard_spent(amount: int, source: String) -> void:
	if not enabled:
		return
	_lines.append("  Shard spent: %d (%s)" % [amount, source])

# kind is a short label ("Card choice", "Rare drop") rather than an
# enum - this is the one place that formats it, nothing downstream ever
# switches on it, so a plain string is simpler than threading LootEntry.
# LootType all the way in here just to match on it once.
func log_reward_offered(kind: String, offered_names: Array[String], taken_name: String) -> void:
	if not enabled:
		return
	var outcome := ("took %s" % taken_name) if taken_name != "" else "skipped"
	_lines.append("  %s offered: %s -> %s" % [kind, ", ".join(offered_names), outcome])

# --- Battles ---

func log_battle_start(enemy_names: Array[String]) -> void:
	if not enabled:
		return
	_lines.append("  Battle: %s" % ", ".join(enemy_names))
	# Per-battle accumulator reset - HERE, not on scene load/autoload
	# _ready() (this function is only ever called once per battle.gd's
	# own _start_battle()), so a run spanning several battles gets an
	# independent count for each one instead of everything accumulating
	# across the whole run.
	_battle_hp_start = RunState.player_hp
	_battle_damage_dealt = 0
	_battle_damage_taken = 0
	_battle_damage_blocked = 0
	_battle_absorb_used = 0
	_battle_toll_accrued = 0
	_battle_toll_peak = 0
	_battle_toll_accrued_enemy = 0
	_battle_toll_accrued_self = 0
	_battle_toll_accrued_status = 0
	_last_toll = 0
	_battle_owed_applied = 0
	_battle_owed_collected = 0
	_battle_owed_lost_on_death = 0
	_battle_index += 1
	_battle_cards_played = 0
	_battle_energy_unspent_total = 0
	_battle_openers_played = 0
	_battle_chain_payoffs_fired = 0
	_battle_chain_expired = 0
	_battle_enemy_names = enemy_names.duplicate()
	_battle_boss_charges_attempted = 0
	_battle_boss_charges_interrupted = 0
	_battle_boss_charges_buffed = 0
	_battle_boss_charge_check_damages = []
	_battle_damage_source_died_turn = -1
	_battle_linked_attack_steps = []
	begin_turn(1, RunState.player_hp)

# Called once per charge WINDOW opening (see battle.gd's _advance_boss_
# charge() - no separate TELEGRAPH turn any more, 2026-08-29 rework) -
# "attempted" means the Charge actually began, not just that the boss's
# own normal-attack countdown reached zero (those are the same moment
# today, but this is what the word in the summary line below is
# describing).
func log_boss_charge_attempted() -> void:
	if not enabled:
		return
	_battle_boss_charges_attempted += 1

# Called once per CHECK (see battle.gd's _advance_boss_charge()) -
# accumulated_damage is whatever landed during the window, checked
# against EnemyCombatant.charge_effective_threshold (already clamped
# against the boss's own remaining HP - see that field's own doc), not
# the raw configured EnemyData.charge_damage_threshold.
func log_boss_charge_check(interrupted: bool, accumulated_damage: int) -> void:
	if not enabled:
		return
	_battle_boss_charge_check_damages.append(accumulated_damage)
	if interrupted:
		_battle_boss_charges_interrupted += 1
	else:
		_battle_boss_charges_buffed += 1

# Called once, from battle.gd's _on_enemy_defeated(), the turn some OTHER
# enemy's own damage_source_enemy reference dies (SUPPLY, for GUN) - see
# _battle_damage_source_died_turn's own doc above for what this is
# actually being watched for. Stays -1 (never called) for a fight that
# never touches this mechanic, or where the source survives to the end.
func log_damage_source_defeated(turn: int) -> void:
	if not enabled:
		return
	_battle_damage_source_died_turn = turn

# Called once per landed ATTACK from an encounter-linked enemy (GUN) -
# see battle.gd's _encounter_linked_damage() for where this value comes
# from. Appended in order, so the printed list below reads as a timeline.
func log_linked_attack_step(damage: int) -> void:
	if not enabled:
		return
	_battle_linked_attack_steps.append(damage)

func log_enemy_spawn(enemy_name: String) -> void:
	if not enabled:
		return
	_lines.append("    (%s joins the fight)" % enemy_name)

# A combat node can resolve three ways now (see battle.gd's own escape
# resolution note) - VICTORY (every enemy defeated), DEFEAT (player HP
# hit 0), or ESCAPE (the encounter ends with neither: the player leaves
# the node, no rewards, the enemy still alive). Nested here rather than
# a standalone global type since this function is the only place that
# actually switches on it - battle.gd's three call sites just construct
# a value and hand it off, the same "enum lives on whichever type
# interprets it" shape StatusEffectData.ModifierOperation/ModifierTarget
# already use.
enum BattleOutcome { VICTORY, DEFEAT, ESCAPE }

func log_battle_end(outcome: BattleOutcome, energy_left: int) -> void:
	if not enabled:
		return
	end_turn(RunState.player_hp, energy_left)
	var result_word: String
	match outcome:
		BattleOutcome.VICTORY:
			result_word = "victory"
		BattleOutcome.DEFEAT:
			result_word = "defeat"
		BattleOutcome.ESCAPE:
			result_word = "escape"
	_lines.append("  Battle result: %s" % result_word)
	# Per-battle summary - everything accumulated since log_battle_start()
	# via the ordinary log_*() calls each event already goes through
	# elsewhere (see this file's own header on that split), not re-derived
	# here from anything.
	_lines.append("  Turns: %d | HP %d->%d | Enemies: %s" % [
		_turn_number, _battle_hp_start, RunState.player_hp, ", ".join(_battle_enemy_names)
	])
	_lines.append("  Damage: dealt %d, taken %d (blocked %d, absorbed %d) | Toll: accrued %d, peak %d" % [
		_battle_damage_dealt, _battle_damage_taken, _battle_damage_blocked, _battle_absorb_used, _battle_toll_accrued, _battle_toll_peak
	])
	# Toll-by-source breakdown (2026-09-02, Toll source tracking pass) - its
	# own line, not appended onto the one above, so the existing "Damage:
	# ..." line never changes shape for anything already parsing it.
	# Always printed (unlike the Boss Charges/Linked damage lines below,
	# which are omitted for a fight that never touches that mechanic) -
	# every fight has SOME Toll split to report, even if every bucket is 0.
	_lines.append("  Toll by source: enemy %d, self %d, status %d" % [
		_battle_toll_accrued_enemy, _battle_toll_accrued_self, _battle_toll_accrued_status
	])
	_csv_rows.append("%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		_battle_index, ";".join(_battle_enemy_names), _turn_number, _battle_hp_start, RunState.player_hp,
		_battle_damage_dealt, _battle_damage_taken, _battle_damage_blocked, _battle_toll_accrued, _battle_toll_peak,
		_battle_toll_accrued_enemy, _battle_toll_accrued_self, _battle_toll_accrued_status, _battle_absorb_used,
		_battle_owed_applied, _battle_owed_collected, _battle_owed_lost_on_death
	])
	_lines.append("  Cards played: %d | Energy unspent (total): %d | Chain: openers %d, payoffs %d, expired %d" % [
		_battle_cards_played, _battle_energy_unspent_total, _battle_openers_played, _battle_chain_payoffs_fired, _battle_chain_expired
	])
	# Owed summary (2026-09-08, Owed status pass) - omitted entirely for
	# every fight that never applies it, same "don't clutter the
	# transcript with a mechanic this fight never touched" instinct the
	# Boss Charge/Linked damage lines below already use - unlike Toll,
	# which every fight has SOME split to report for, Owed is opt-in
	# (exactly one card grants it) so a 0/0/0 line in every ordinary
	# fight's log for the rest of this game's life isn't warranted.
	if _battle_owed_applied > 0:
		_lines.append("  Owed: applied %d, collected %d, lost on death %d" % [
			_battle_owed_applied, _battle_owed_collected, _battle_owed_lost_on_death
		])
	# Boss Charge summary (2026-08-29, BOSS_01 pass) - omitted entirely for
	# every fight that never attempted one, same "don't clutter the
	# transcript with a mechanic this fight never touched" instinct as
	# every other conditional line in this file's own history, rather
	# than an always-printed "attempted 0" line in every ordinary fight's
	# log for the rest of this game's life.
	if _battle_boss_charges_attempted > 0:
		_lines.append("  Boss Charges: attempted %d, interrupted %d, buffed %d | Check damages: %s" % [
			_battle_boss_charges_attempted, _battle_boss_charges_interrupted, _battle_boss_charges_buffed, _battle_boss_charge_check_damages
		])
	# GUN/SUPPLY summary (2026-08-29) - omitted for every fight that never
	# touches this mechanic, same instinct as the Boss Charge line above.
	# Turns logged here alongside the fight's own overall Turns count
	# (further up this same block) is exactly the comparison this
	# encounter's own design report flagged as unresolved: SUPPLY-first is
	# EXPECTED to be somewhat favored at today's numbers, not proven to
	# be - see _battle_damage_source_died_turn's own doc for what a real
	# sample should look like if the fork is actually real.
	if not _battle_linked_attack_steps.is_empty():
		var source_fate: String = "survived" if _battle_damage_source_died_turn < 0 else "died turn %d" % _battle_damage_source_died_turn
		_lines.append("  Linked damage: source %s | Attack steps: %s" % [source_fate, _battle_linked_attack_steps])
	_lines.append("")

# --- Per-turn accumulator ---
#
# One turn (see battle.gd's own turn loop note) is "the player's turn,
# then whatever the enemy/enemies do in response" - begin_turn() opens
# it (called once from log_battle_start() for turn 1, and again at the
# start of every subsequent player turn), end_turn() closes and writes
# it (called at the start of the NEXT turn, and again at battle end to
# flush whichever turn was still open). _turn_active guards end_turn()
# against running with nothing open - harmless either way, but keeps
# a stray extra call from ever writing a bogus empty-looking line.

func begin_turn(turn_number: int, hp: int) -> void:
	if not enabled:
		return
	_turn_active = true
	_turn_number = turn_number
	_turn_hp_before = hp
	_turn_damage_dealt = 0
	_turn_damage_taken = 0
	_turn_cards_played.clear()

func log_card_played(card_name: String, chain_note: String = "") -> void:
	if not enabled or not _turn_active:
		return
	_turn_cards_played.append(card_name if chain_note == "" else "%s (%s)" % [card_name, chain_note])
	_battle_cards_played += 1

func log_damage_dealt(amount: int) -> void:
	if not enabled or not _turn_active or amount <= 0:
		return
	_turn_damage_dealt += amount
	_battle_damage_dealt += amount

func log_damage_taken(amount: int) -> void:
	if not enabled or not _turn_active or amount <= 0:
		return
	_turn_damage_taken += amount
	_battle_damage_taken += amount

# The blocked half of an incoming attack - see battle.gd's own
# _enemy_attack_player(), the only source of block interactions (self-
# damage and status ticks both bypass block entirely, so they never call
# this). Unlike log_damage_taken() above, this counts a FULLY blocked hit
# too (0 got through, but the block still did its job) - called
# unconditionally by that call site rather than nested inside its own
# "did any damage get through" branch, so a full block isn't silently
# dropped from the total the way it would be if this reused that guard.
func log_damage_blocked(amount: int) -> void:
	if not enabled or amount <= 0:
		return
	_battle_damage_blocked += amount

# Absorb's own counterpart to log_damage_blocked() above (2026-09-05,
# Forbearance pass) - same shape exactly: called unconditionally from
# battle.gd's own _enemy_attack_player() with result["absorbed_by_
# absorb"], guarded here (not at the call site) so a hit that spent none
# of the pool (0) is silently skipped, same as a hit that landed no
# block at all skips log_damage_blocked() above.
func log_absorb_used(amount: int) -> void:
	if not enabled or amount <= 0:
		return
	_battle_absorb_used += amount

# --- Owed (2026-09-08, Owed status pass) ---
#
# Three counters read together (see _battle_owed_applied's own doc) -
# applied (battle.gd's APPLY_STATUS_TO_TARGET branch, by the status's own
# default_magnitude), collected (battle.gd's _collect_owed(), once per
# heal actually fired - not per stack removed and per HP, since those are
# always 1 and 2 respectively today; a raw event count is what "heals
# fired" in this feature's own brief is asking for), and lost-on-death
# (battle.gd's _on_enemy_defeated(), the magnitude still on the status
# the instant its holder dies, before _clear_combatant_statuses() wipes
# it - see that call site's own doc for why the read has to happen
# there specifically).
func log_owed_applied(amount: int) -> void:
	if not enabled or amount <= 0:
		return
	_battle_owed_applied += amount

func log_owed_collected() -> void:
	if not enabled:
		return
	_battle_owed_collected += 1

func log_owed_lost_on_death(amount: int) -> void:
	if not enabled or amount <= 0:
		return
	_battle_owed_lost_on_death += amount

# Which of the three real HP-loss paths caused an accrued Toll delta
# (2026-09-02, Toll source tracking pass) - battle.gd's _set_player_hp()
# receives this from ITS OWN caller and threads it through _set_toll()
# into log_toll_change() below, same "told, not asked" split every other
# piece of state reaches this file through. SELF is the default both here
# and on _set_player_hp()'s own parameter - every accrual path that
# actually exists today (_deal_self_damage(), the SELF_DAMAGE_TOLL top-up)
# is tagged explicitly regardless, so the default only matters for a
# future call site that forgets to - falling back to SELF (rather than a
# fourth UNSPECIFIED bucket nothing downstream reads) keeps the three
# per-source accumulators below always summing to _battle_toll_accrued
# exactly, with no silently-uncounted bucket.
enum TollSource { ENEMY, SELF, STATUS }

# Called with Toll's own new value every time battle.gd changes it (6
# call sites - accrual in _set_player_hp(), the SELF_DAMAGE_TOLL top-up,
# and the TOLL_DAMAGE/TOLL_BLOCK/TOLL_RETALIATE spends, plus the battle-
# start reset - see each one's own sibling call to this, right alongside
# the existing player_resource_cluster.update_toll() push). Compares
# against the LAST value THIS function was told (_last_toll, not
# RunState/battle.gd's own toll var - this file has no reason to read
# battle state directly, same "told, not asked" split as everywhere else
# here) to turn "the new total" into "how much this specific change
# added" - only a positive delta counts toward accrued (a spend is a
# negative delta, correctly ignored, not counted as negative accrual).
# Peak just tracks the highest value seen regardless of direction.
# `source` (see TollSource's own doc above) only ever matters on that same
# positive-delta branch - a spend's source is never asked, so a spend
# call site passing the default is exactly as correct as one that bothers
# to tag itself.
func log_toll_change(new_toll: int, source: TollSource = TollSource.SELF) -> void:
	if not enabled:
		return
	var delta := new_toll - _last_toll
	if delta > 0:
		_battle_toll_accrued += delta
		match source:
			TollSource.ENEMY:
				_battle_toll_accrued_enemy += delta
			TollSource.SELF:
				_battle_toll_accrued_self += delta
			TollSource.STATUS:
				_battle_toll_accrued_status += delta
	_battle_toll_peak = maxi(_battle_toll_peak, new_toll)
	_last_toll = new_toll

# battle.gd's _update_chain_state() - the OPENER branch specifically,
# counting every Opener PLAYED, even a "wasted" one played while already
# empowered (see that function's own doc on why a second Opener has
# nothing further to set) - "openers played," not "times empowerment
# actually flipped false-to-true."
func log_opener_played() -> void:
	if not enabled:
		return
	_battle_openers_played += 1

# battle.gd's _trigger_chain_payoff() - called right where that function
# actually resolves the payoff (_resolve_card_effect()), not merely
# where it was ENTERED - a payoff that bails out early (battle already
# over, or a DAMAGE/STUN payoff whose target died during the delay - see
# that function's own guards) never actually fired, so it isn't counted.
func log_chain_payoff_fired() -> void:
	if not enabled:
		return
	_battle_chain_payoffs_fired += 1

# battle.gd's _discard_entire_hand() - only when chain_empowered was
# actually true right before that function clears it; nothing "expires"
# from an already-false state, so that call site checks first rather
# than this counting every end-of-turn clear unconditionally.
func log_chain_expired() -> void:
	if not enabled:
		return
	_battle_chain_expired += 1

func end_turn(hp_after: int, energy_left: int) -> void:
	if not enabled or not _turn_active:
		return
	var played := ", ".join(_turn_cards_played) if not _turn_cards_played.is_empty() else "(none)"
	_lines.append("    Turn %d: HP %d->%d | dealt %d, took %d | played: %s" % [
		_turn_number, _turn_hp_before, hp_after, _turn_damage_dealt, _turn_damage_taken, played
	])
	_battle_energy_unspent_total += energy_left
	_turn_active = false

# --- Shared helpers ---

func _deck_summary_line(label: String, deck: Array[CardData]) -> String:
	var counts: Dictionary = {}
	for card in deck:
		counts[card.card_name] = counts.get(card.card_name, 0) + 1
	var parts: Array[String] = []
	for card_name in counts:
		parts.append("%dx %s" % [counts[card_name], card_name])
	return "%s (%d cards): %s" % [label, deck.size(), ", ".join(parts)]

# YYYYMMDD_HHMMSS from the system clock - sortable by filename, which a
# plain locale-formatted date/time string wouldn't be.
func _timestamp() -> String:
	var d := Time.get_date_dict_from_system()
	var t := Time.get_time_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [d.year, d.month, d.day, t.hour, t.minute, t.second]

func _write_to_file() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_FOLDER)
	# One shared timestamp for both files below (2026-09-02, CSV sidecar
	# pass) - computed once here rather than letting each file build its
	# own path off a separate _timestamp() call, so run_TIMESTAMP.txt and
	# run_TIMESTAMP.csv from the same run always share the exact same
	# TIMESTAMP, not two calls a second apart landing on different values.
	var timestamp := _timestamp()
	var path := "%srun_%s.txt" % [LOG_FOLDER, timestamp]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("RunLogger: couldn't open %s for writing (error %d)." % [path, FileAccess.get_open_error()])
		return
	file.store_string("\n".join(_lines))
	file.close()
	print("RunLogger: wrote %s" % ProjectSettings.globalize_path(path))

	var csv_path := "%srun_%s.csv" % [LOG_FOLDER, timestamp]
	var csv_file := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv_file == null:
		push_error("RunLogger: couldn't open %s for writing (error %d)." % [csv_path, FileAccess.get_open_error()])
		return
	csv_file.store_string("\n".join(_csv_rows))
	csv_file.close()
	print("RunLogger: wrote %s" % ProjectSettings.globalize_path(csv_path))
