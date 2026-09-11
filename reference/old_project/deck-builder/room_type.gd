extends RefCounted
class_name RoomType
# Standalone, not nested inside RoomState, so this enum can be used as a
# real TYPE elsewhere (e.g. a function parameter or @export field type),
# not just a value. A type annotation needs to resolve against a genuine
# class_name'd type; RoomState is an autoload SINGLETON INSTANCE, not a
# registered class, so code outside room_state.gd could read
# RoomState.current_room_type fine as a VALUE but not reliably use
# RoomState's own nested enum as a TYPE. Same shape as CardEffect/
# EnemyIntent: a tiny class whose only job is holding one enum.

enum Kind { COMBAT, TREASURE, EVENT, SHOP, ELITE, BOSS, HEAP, FORGE }
# Every room's type comes from RunState's run graph now (see
# run_state.gd's _generate_run_graph()) - BOSS is placed deliberately, as
# the graph's single final node, rather than ever being rolled at random
# like the others. ELITE is placed deliberately too (1-2 per run, in a
# fixed layer range - see _assign_room_types()), a routing fork rather
# than a chance an ordinary COMBAT roll happens to hit an elite enemy -
# see DESIGN.md's ELITE Rooms section for why.
#
# HEAP (2026-08-28, wreckage-heap room v1) - a wreckage pile the player
# sifts through for salvage, part of the same leftover weighted roll
# combat_weight/treasure_weight/event_weight already feed (see run_
# state.gd's own heap_weight and room_type_max_instances), not a
# guaranteed-once placement like SHOP/TREASURE/EVENT.
#
# FORGE (2026-09-02, forge pass) - a workbench where upgrade shards get
# spent on a card upgrade (see field_forge.gd, CardUpgradeService). Same
# leftover-weighted-roll shape HEAP already established, not guaranteed:
# run_state.gd's own forge_weight feeds the same weights dict, and it's
# capped (room_type_max_instances) the same way HEAP is, just with no
# minimum - a run can have zero forge rooms, unlike HEAP's guaranteed-
# at-least-one.

# The single source of truth for a room type's PLAYER-FACING label
# (2026-08-31, label-unification pass) - REPLACES three independent
# hand-copied name mappings that had already drifted apart (map_screen.
# gd's own _type_name(), run_hud.gd's _room_type_display_name(), and
# run_state.gd's now-removed SUNKEN_WORKS_ROOM_NAMES/_pick_display_name())
# with one dictionary both callers read. Deliberately does NOT cover
# run_state.gd's own _type_name() (the dev graph print, still "COMBAT"/
# "TREASURE"/... verbatim) or run_logger.gd's RoomType.Kind.keys()
# introspection - those are log-facing, already persisted to run_logs/ in
# that exact uppercase format, and changing their output would make old
# and new logs disagree on spelling for no player-facing benefit. This
# dictionary is ONLY for what a player actually reads (the map screen and
# the field HUD header).
const DISPLAY_NAMES := {
	Kind.COMBAT: "Open Ground",
	Kind.ELITE: "Standing Water",
	Kind.HEAP: "Dunes",
	Kind.TREASURE: "Hidden Cache",
	Kind.SHOP: "The Collector",
	Kind.EVENT: "Event",
	Kind.BOSS: "The Headland",
	Kind.FORGE: "Forge",
	# "Forge" is a placeholder label (2026-09-02, forge pass) - every other
	# entry here is a real, biome-voiced name ("Standing Water," "The
	# Collector"); this one is a plain functional noun, deliberately not
	# yet given the same world-voice treatment - see field_forge.gd's own
	# header for the rest of this pass's placeholder-content flags.
}

# "?" for an invalid/out-of-range kind, matching every other room-type
# formatter in this project's own existing "?" fallback (map_screen.gd's
# _type_name(), run_state.gd's own _type_name()) rather than inventing a
# new placeholder convention here.
static func display_name(kind: Kind) -> String:
	return DISPLAY_NAMES.get(kind, "?")
