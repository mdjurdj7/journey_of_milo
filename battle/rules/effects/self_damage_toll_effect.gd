extends RefCounted
class_name SelfDamageTollEffect

# Loses up to `value` HP, floored so it can never drop the player below 1
# (unlike plain SelfDamageEffect, which can kill) - and grants exactly
# `toll_gain` Toll in TOTAL, topping up whatever the floor-clamped loss
# already accrued on its own.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var before := ctx.player.hp
	var floored_loss: int = mini(effect.value, before - 1)
	if floored_loss > 0:
		var lost := DamagePipeline.apply_bypass(floored_loss, ctx.player)
		if lost > 0:
			ctx.player.toll += lost
			ctx.player.took_damage_this_turn = true
			ctx.report_damage(ctx.player, lost, "self")
	var actual_lost := before - ctx.player.hp
	var toll_topup: int = effect.toll_gain - actual_lost
	if toll_topup > 0:
		ctx.player.toll += toll_topup
