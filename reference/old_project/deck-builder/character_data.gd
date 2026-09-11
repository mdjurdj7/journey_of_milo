extends Resource
# Same pattern as CardData/EnemyData (see card_data.gd/enemy_data.gd): a
# plain data container, not a node - one instance per playable class.

class_name CharacterData

@export var character_name: String = ""
# The class's name, e.g. "Wanderer". Not shown anywhere yet (there's no
# character-select UI), but RunState.current_class needs SOME identifier
# for later dev-aid printing/debugging.

@export var card_pool_folder: String = ""
# Where this class's reward-pool cards live, e.g.
# "res://resources/cards/classes/wanderer/" - reward_screen.gd's
# _load_reward_pool() folder-scans exactly this directory (same "drop a
# .tres in, it's in the pool automatically" convenience the old shared
# resources/cards/rewards/ folder had, just scoped to one class now) for
# whichever class RunState.current_class is. Pools are fully separate per
# class (Slay the Spire-style) - there's no shared/neutral reward pool
# anymore. Never touches the starting deck (see run_state.gd's
# STARTING_DECK, which is still universal regardless of class).

@export var rally_recovery_percent: int = 0
# This class's innate passive - Rally: recover this percent of every
# point of HP damage the player deals, rounded down, capped at
# whatever's currently in battle.gd's rally_pool (never a free heal -
# see that var's own doc for what actually fills it and why self-
# damage never does). 0 (the default) means no passive at all - only
# the Wanderer sets this so far (see DESIGN.md's Wanderer entry -
# "Lifesteal and drain effects" is the first listed Core concept).
# Checked in battle.gd's _deal_damage_to_enemy(), THE one seam every
# outgoing player damage source already funnels through (an ordinary
# card, Toll consumption, a chain payoff, a weapon reflect, a
# Retaliation proc), so recovery fires for all of them uniformly with
# no per-source special-casing - only the pool cap (not this percent)
# decides whether any of them actually pay out. A plain int rather
# than a whole passive-effect Resource type because exactly one
# passive exists right now - same "don't build the abstraction before
# a second thing needs it" reasoning StatusEffectData's own header
# already applies elsewhere. Replaced flat lifesteal_percent
# (2026-08-24 -> corrected same day): flat lifesteal healed off EVERY
# hit unconditionally, which wasn't what Rally was specced to be - see
# rally_pool's own doc for the corrected mechanic.
