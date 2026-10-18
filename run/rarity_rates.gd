extends Resource
class_name RarityRates

# One set of per-slot odds for a card offer's rarity tiers - relative
# weights, renormalised over the tiers that still have an eligible card
# (RewardPool.pick_rarity()), so an empty tier never hands its share to a
# single other. A FightRarityTable step's rates: what a normal fight's
# offer rolls with on its floors, in place of the pool's own rates.

@export var common_rate: float = 60.0:
	set(value):
		common_rate = value
		emit_changed()
@export var uncommon_rate: float = 30.0:
	set(value):
		uncommon_rate = value
		emit_changed()
@export var rare_rate: float = 9.0:
	set(value):
		rare_rate = value
		emit_changed()
@export var ultra_rare_rate: float = 1.0:
	set(value):
		ultra_rare_rate = value
		emit_changed()

func rate_for(tier: CardData.CardRarity) -> float:
	match tier:
		CardData.CardRarity.COMMON:
			return common_rate
		CardData.CardRarity.UNCOMMON:
			return uncommon_rate
		CardData.CardRarity.RARE:
			return rare_rate
		CardData.CardRarity.ULTRA_RARE:
			return ultra_rare_rate
	return 0.0
