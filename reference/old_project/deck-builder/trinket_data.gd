extends Resource
class_name TrinketData
# Same pattern as WeaponData (see weapon_data.gd): a plain data
# container, not a node - one instance per trinket, defined once as a
# .tres file. A sibling equipment slot, not a variant of the weapon slot
# - see run_state.gd's own equipped_weapon doc for why equipped_trinket
# is a second field, not a restructure of the first ("parallel fields,
# not one polymorphic system").

@export var trinket_name: String = ""

@export var rarity: CardData.Rarity = CardData.Rarity.COMMON
# Reuses the same shared tier list weapons/cards already use, for the
# same reason WeaponData.rarity does - see its own note.

@export_multiline var description: String = ""
# Lore text ONLY, same split WeaponData.description already establishes
# - the mechanical effect is generated from structured data (see
# modifier/TrinketModifier.describe()), not hand-written here.

@export var modifier: TrinketModifier = null
# What this trinket actually does - see trinket_modifier.gd. Null is a
# legal (if pointless) trinket, same "empty means no effect" shape
# WeaponData.modifier already uses.

@export var icon_texture: Texture2D = null
# The trinket's illustration - optional, same "empty means no art" shape
# WeaponData.icon_texture already uses. No UI reads this yet (see this
# feature's own scope note: no pickup/loot/reward/deck-viewer UI built
# for trinkets in this pass) - included now so a future UI pass has
# somewhere to read it from without a second field-adding pass later.
