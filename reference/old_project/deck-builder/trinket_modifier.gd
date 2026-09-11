extends Resource
class_name TrinketModifier
# What a trinket actually DOES - same shape as WeaponModifier (see
# weapon_modifier.gd): one Resource, an enum saying what kind, a value.
# Deliberately mirrors that file's own structure rather than inventing a
# separate equipment-effect convention, per this feature's own brief.
#
# No TargetScope equivalent, unlike WeaponModifier - that field exists
# there because CATEGORY_DAMAGE/CATEGORY_ENERGY_COST need to know WHICH
# cards they apply to. TOLL_THRESHOLD_FREE_CARD (below) applies to
# whatever card is played next, no filtering by card at all, so nothing
# here needs one yet - same "don't build the abstraction before a second
# thing needs it" reasoning CharacterData.rally_recovery_percent's own
# doc already applies. Add one only once a future Kind actually needs to
# scope by card.

enum Kind { TOLL_THRESHOLD_FREE_CARD }
# TOLL_THRESHOLD_FREE_CARD - the first time the player's Toll crosses
#                     `value` UPWARD in a single combat, arms a one-shot
#                     flag: the next card played (whichever it is, even
#                     one that already costs 0) costs no energy, then the
#                     flag clears. Fires once per combat, not once per
#                     crossing - Toll can be spent and re-accrued past
#                     the threshold again without re-arming. The crossing
#                     itself is detected in battle.gd's own _set_toll()
#                     (the single choke point every Toll change already
#                     routes through), not duplicated at any individual
#                     accrual site.

@export var kind: Kind = Kind.TOLL_THRESHOLD_FREE_CARD
@export var value: int = 25
# Only read by TOLL_THRESHOLD_FREE_CARD above - the Toll THRESHOLD that
# arms the flag, not a damage/cost delta the way WeaponModifier's own
# value usually is. Same "one shared field name, meaning depends on
# kind" shape WeaponModifier's own value already uses (see its own
# SELF_DAMAGE_REFLECT note, which reads value not at all, for the
# precedent of a Kind that repurposes - or ignores - the shared field).

# A human-readable line describing what this modifier does, generated
# from the data rather than hand-authored - same reasoning WeaponModifier
# .describe() already documents (see weapon_modifier.gd and WeaponData.
# description's own note on why lore text and mechanical text are two
# separate concerns). No UI reads this yet (see this feature's own scope
# note: no pickup/loot/reward/deck-viewer UI built for trinkets in this
# pass) - included now so a future UI pass has the same generated-text
# convention weapons already use, rather than needing to invent it then.
func describe() -> String:
	match kind:
		Kind.TOLL_THRESHOLD_FREE_CARD:
			return "The first time Toll reaches %d, your next card costs no energy" % value
		_:
			return ""
