extends RefCounted
class_name Skillchain

# The Samurai's chain, by card property (CardData.ChainProperty): ADVANCE
# -> HOLD -> WITHDRAW -> ADVANCE. A card whose property follows the last
# chained card's extends the chain a level and fires the link's
# skillchain, after the card's own effects (EffectResolver.resolve_card()):
#   ADVANCE -> HOLD     Parry   - Block, per level
#   HOLD -> WITHDRAW    Recover - draw
#   WITHDRAW -> ADVANCE Lunge   - damage per level to the card's target;
#                                 nothing with that target down
# A card with no property ends the chain; one with the wrong property
# starts a new one at level 0. The chain is the player's, per turn - kept
# on the Combatant, stepped at a play's commit (BattleController._resolve_
# play()), never by a replay, and cleared as a turn ends and begins.

const PARRY := &"Parry"
const RECOVER := &"Recover"
const LUNGE := &"Lunge"

# The property that extends a chain whose last card was `last`.
static func next_property(last: CardData.ChainProperty) -> CardData.ChainProperty:
	match last:
		CardData.ChainProperty.ADVANCE:
			return CardData.ChainProperty.HOLD
		CardData.ChainProperty.HOLD:
			return CardData.ChainProperty.WITHDRAW
		CardData.ChainProperty.WITHDRAW:
			return CardData.ChainProperty.ADVANCE
	return CardData.ChainProperty.NONE

# The skillchain of the link that ends on `played`.
static func link_into(played: CardData.ChainProperty) -> StringName:
	match played:
		CardData.ChainProperty.HOLD:
			return PARRY
		CardData.ChainProperty.WITHDRAW:
			return RECOVER
		CardData.ChainProperty.ADVANCE:
			return LUNGE
	return &""

# `card` has been played: the chain steps. Returns the skillchain the link
# fired, or &"" for none. last_skillchain is the live chain's alone: a
# break clears it, so nothing names a skillchain of a chain that's gone.
static func step(player: Combatant, card: CardData) -> StringName:
	var played: CardData.ChainProperty = card.chain_property if card != null else CardData.ChainProperty.NONE
	if played == CardData.ChainProperty.NONE:
		reset(player)
		return &""
	if player.chain_property != CardData.ChainProperty.NONE and played == next_property(player.chain_property):
		player.chain_level += 1
		player.chain_property = played
		player.last_skillchain = link_into(played)
		return player.last_skillchain
	player.chain_level = 0
	player.chain_property = played
	player.last_skillchain = &""
	return &""

# No chain, and no skillchain fired yet - a turn's end and start, and a
# card with no property.
static func reset(player: Combatant) -> void:
	player.chain_level = 0
	player.chain_property = CardData.ChainProperty.NONE
	player.last_skillchain = &""

# What `link` resolves at `level`, by the player's numbers (CharacterData's,
# copied by BattleController.setup()): a CardEffect for the resolver, or
# null for no link.
static func payoff(link: StringName, level: int, player: Combatant) -> CardEffect:
	var effect := CardEffect.new()
	match link:
		PARRY:
			effect.effect_type = CardEffect.EffectType.BLOCK
			effect.value = player.parry_block_per_level * level
		RECOVER:
			effect.effect_type = CardEffect.EffectType.DRAW
			effect.value = player.recover_draw
		LUNGE:
			effect.effect_type = CardEffect.EffectType.DAMAGE
			effect.value = player.lunge_damage_per_level * level
		_:
			return null
	return effect

# Whether a Lunge has `target` to land on: one living and unburied. The
# card's own blow may have killed it - DamageEffect would hit it again.
static func target_standing(target: Combatant) -> bool:
	return target != null and target.hp > 0 and not target.is_out_of_reach()
