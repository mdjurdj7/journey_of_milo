extends Resource
class_name WeaponModifier
# What a weapon actually DOES - a small closed set of shapes, not an
# open-ended effect system, per DESIGN.md's Equipment note. Deliberately
# mirrors CardEffect's own "one Resource, an enum saying what kind, a
# value" shape (see card_effect.gd), extended with a TargetScope for the
# two shapes that need to know WHICH cards they apply to.

enum Kind { CATEGORY_DAMAGE, CHAIN_PAYOFF_DAMAGE, CATEGORY_ENERGY_COST, SELF_DAMAGE_REFLECT }
# CATEGORY_DAMAGE   - +value damage on DAMAGE-type card effects, for
#                     cards matching target_scope. Resolved in battle.gd's
#                     _resolve_card_effect(), via _weapon_modified_value().
# CHAIN_PAYOFF_DAMAGE - +value damage on a chain's own payoff hit
#                     (_trigger_chain_payoff()) - but ONLY when that
#                     payoff is itself DAMAGE-type. A Closer whose own
#                     payoff is a HEAL (no card sets one today - see
#                     card_data.gd's chain_followup_effect note) would be
#                     untouched by this - not a bug, a real scope edge:
#                     a weapon about striking harder shouldn't also
#                     inflate a sustain effect. Ignores target_scope
#                     entirely (the payoff isn't "a card" being played,
#                     there's nothing to filter by).
# CATEGORY_ENERGY_COST - -value energy cost (never below 0) for cards
#                     matching target_scope. Resolved everywhere battle.
#                     gd reads CardData.energy_cost - see its own
#                     _effective_energy_cost().
# SELF_DAMAGE_REFLECT - whenever a card's own SELF_DAMAGE effect
#                     resolves, deals that SAME amount to the card's
#                     target as a separate follow-up hit (see battle.
#                     gd's _reflect_self_damage()) - "the cost becomes
#                     damage." A genuinely different shape from the
#                     other three: it doesn't adjust a number on the
#                     effect that's resolving, it triggers a SECOND,
#                     independent hit off a DIFFERENT effect type
#                     entirely. Ignores target_scope (no "which cards" -
#                     every SELF_DAMAGE effect qualifies) AND ignores
#                     value (the brief is a strict 1:1 mirror, not a
#                     tunable multiplier - overloading value with
#                     different math than every other Kind uses it for
#                     would be more confusing than just not using it).
#                     No-ops if the card has no target (a SELF_DAMAGE-
#                     only card with no DAMAGE effect of its own never
#                     asked for one - see _card_needs_target()).
#
# ADDING A 5th KIND LATER: add the enum value, add one case wherever
# _weapon_modified_value()/the chain-payoff check dispatch on kind (or,
# if the new shape doesn't fit "adjust one number" - e.g. a structural
# rule like "draw an extra card" - a small dedicated hook elsewhere, the
# same way HEAL needed no new machinery for a card effect but a
# hypothetical DRAW-type payoff would need its own case, and SELF_
# DAMAGE_REFLECT needed its own dedicated function rather than reusing
# _weapon_modified_value()). The PATTERN generalizes; not every future
# shape will fit the existing numeric helpers unchanged.

enum TargetScope { ALL_ATTACKS, OPENERS, CLOSERS }
# Which cards a CATEGORY_* modifier cares about - a small purpose-built
# enum, not a reuse of CardData.CardType/ChainRole directly. A future
# modifier might want to filter on something neither of those expresses
# (e.g. "0-cost cards") - keeping this independent means that never
# touches CardData. Unused by CHAIN_PAYOFF_DAMAGE.

@export var kind: Kind = Kind.CATEGORY_DAMAGE
@export var target_scope: TargetScope = TargetScope.ALL_ATTACKS
@export var value: int = 0

# A human-readable line describing what this modifier does, generated
# from the data rather than hand-authored - see WeaponData.description's
# own note on why lore text and mechanical text are two separate
# concerns here. Shown in the loot row, the equip/swap overlay, and
# DeckViewer's equipped-weapon section - one place decides the wording,
# so retuning how a shape reads never means hunting through three UI
# scripts.
func describe() -> String:
	match kind:
		Kind.CATEGORY_DAMAGE:
			return "%s deal +%d damage" % [_scope_text(), value]
		Kind.CHAIN_PAYOFF_DAMAGE:
			return "Chain payoffs deal +%d damage" % value
		Kind.CATEGORY_ENERGY_COST:
			return "%s cost %d less energy" % [_scope_text(), value]
		Kind.SELF_DAMAGE_REFLECT:
			return "HP costs also deal damage to the enemy"
		_:
			return ""

func _scope_text() -> String:
	match target_scope:
		TargetScope.ALL_ATTACKS:
			return "Attacks"
		TargetScope.OPENERS:
			return "Openers"
		TargetScope.CLOSERS:
			return "Closers"
		_:
			return "Cards"
