extends Resource
class_name WeaponData
# Same pattern as CardData/EnemyData (see card_data.gd): a plain data
# container, not a node - one instance per weapon, defined once as a
# .tres file. See DESIGN.md's Equipment note for the design direction
# this implements: equipment MODIFIES how existing cards behave, it
# doesn't grant stats or cards.

@export var weapon_name: String = ""

@export var rarity: CardData.Rarity = CardData.Rarity.COMMON
# Reuses CardData's own Rarity enum directly (COMMON/RARE/ULTRA_RARE/
# SECRET_RARE) rather than a separate equipment-only tier list - DESIGN.
# md's Pillar 3 note already treats these tiers as shared between cards
# and equipment. Drives the same border-color language card.gd's
# RARITY_BORDER_COLORS already uses, reused as-is rather than a second
# copy for weapons.

@export_multiline var description: String = ""
# Lore text ONLY - per the lore-through-items pillar (Pillar 3/4(b)),
# not a rules-text field. Deliberately does NOT also carry the
# mechanical effect the way a card's own description sometimes reads
# like flavor-plus-rules - see `modifier` below, and WeaponModifier.
# describe(), for why the mechanical line is generated from structured
# data instead of hand-written here. This is what a card's own
# description and a weapon's description are free to do differently:
# a card's rules ARE its text; a weapon's rules are data, and its text
# is purely tone.

@export var modifier: WeaponModifier = null
# What this weapon actually does - see weapon_modifier.gd. Null is a
# legal (if pointless) weapon: every resolution hook that reads this
# treats a missing modifier as "no effect," same "empty means
# unaffected" shape used everywhere else in this codebase.

@export var icon_texture: Texture2D = null
# The weapon's illustration - optional, same "empty means no art" shape
# CardData.art_texture already uses (see card_data.gd), and the same
# "placeholder-quality expected during development" caveat. Assets are
# expected to live in assets/equipment/weapons/, mirroring assets/
# cards/art/'s own convention. Shown considerably larger than a card's
# own inline art slot, wherever the weapon itself is the thing on
# display (a loot row claiming it, the equip/swap comparison, the
# equipped-weapon readout) - see loot_row.gd's _update_icon() and
# reward_screen.gd's _populate_weapon_panel() for exactly where. Left
# null, every one of those falls back to exactly how it rendered before
# this field existed - a name and generated effect text, nothing
# missing or broken.
