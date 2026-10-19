extends RefCounted
class_name GainEnergyEffect

# Not capped at max_energy: Energy gained in a turn can stand above it
# (BattleResources shows the extra pips), and the turn start sets it back
# to the turn's own Energy whatever was left (BattleController).
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	ctx.player.energy += maxi(effect.value, 0)
