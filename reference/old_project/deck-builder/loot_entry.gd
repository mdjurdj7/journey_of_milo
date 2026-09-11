extends RefCounted
class_name LootEntry
# Unlike CardData/EnemyData/CardEffect (which all extend Resource so they
# can be saved as .tres files and hand-authored in the Inspector), a loot
# entry is never saved anywhere or edited by hand - it only exists for
# the few seconds between "Battle rolls this battle's rewards" and "the
# player has claimed or left them," created fresh in code every time.
# RefCounted is Godot's plain, lightweight base class for exactly that: a
# throwaway data object that just needs to live in memory and get
# garbage-collected once nothing references it anymore, without any of
# Resource's saving/editing machinery, which this has no use for.

enum LootType { GOLD, CARD_REWARD, RARE_CARD_DROP, WEAPON }
# Adding a new reward type later means adding one more value here, one
# more branch in reward_screen.gd's _claim_entry(), and a create_*()
# factory below - the row display and claiming flow don't change at
# all, since neither of them cares what the type actually is.
# RARE_CARD_DROP and WEAPON are both proof of that: each slotted in
# exactly this way (see DESIGN.md's Rewards note on cards as drops, and
# its Equipment note).

var loot_type: LootType
var claimed: bool = false

# Meaningful for RARE_CARD_DROP (true if the player chose "Leave" in the
# reveal overlay - see reward_screen.gd's _on_rare_leave_pressed()) and
# for WEAPON (true if the player chose "Leave Behind" on the weapon
# reward screen rather than equipping this one - see reward_screen.gd's
# _on_weapon_pickup_resolved()). For RARE_CARD_DROP a declined entry
# still counts as `claimed` (resolved, doesn't block Continue, can't be
# re-opened) - this just tells LootRow which of the two outcomes to show.
# WEAPON is the one exception to "declined implies claimed": a CHEST-
# sourced weapon that's left behind stays UNCLAIMED on purpose, so its
# row remains reclaimable (see _on_weapon_pickup_resolved()'s own note) -
# `declined` there only feeds RunLogger's record of what happened, not
# whether Continue is blocked. A weapon from any other source (no row to
# begin with) still marks `claimed` regardless of `declined`, unchanged.
var declined: bool = false

# Populated only when loot_type == GOLD.
var gold_amount: int = 0

# Populated only when loot_type == CARD_REWARD - the choices are rolled
# once, up front, and just sit here until the row is opened and one is
# picked (or skipped).
var card_choices: Array[CardData] = []

# Populated only when loot_type == RARE_CARD_DROP - a single card, not a
# choice list. This is a gift, not a pick: claiming the row adds this
# exact card to the deck, no alternatives offered.
var rare_drop_card: CardData

# Populated only when loot_type == WEAPON - a single weapon. A weapon
# from the Pay House or a title-screen dev-grant still never becomes a
# row (it opens its own dedicated Equip/Leave Behind screen immediately,
# see reward_screen.gd's _ready()); a CHEST-sourced weapon DOES become a
# row like everything else (2026-08-25 rework, see DESIGN.md's Rewards
# note) - clicking it is what opens that same screen instead.
var weapon_data: WeaponData

# Named "constructors" so call sites read as what they mean
# (LootEntry.create_gold(18)) instead of manually setting fields and
# hoping nothing was missed.
static func create_gold(amount: int) -> LootEntry:
	var entry := LootEntry.new()
	entry.loot_type = LootType.GOLD
	entry.gold_amount = amount
	return entry

static func create_card_reward(choices: Array[CardData]) -> LootEntry:
	var entry := LootEntry.new()
	entry.loot_type = LootType.CARD_REWARD
	entry.card_choices = choices
	return entry

static func create_rare_card_drop(card: CardData) -> LootEntry:
	var entry := LootEntry.new()
	entry.loot_type = LootType.RARE_CARD_DROP
	entry.rare_drop_card = card
	return entry

static func create_weapon_drop(weapon: WeaponData) -> LootEntry:
	var entry := LootEntry.new()
	entry.loot_type = LootType.WEAPON
	entry.weapon_data = weapon
	return entry
