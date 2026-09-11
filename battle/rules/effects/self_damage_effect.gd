extends RefCounted
class_name SelfDamageEffect

# Bypasses block and absorb entirely - can kill. See damage_pipeline.gd's
# apply_bypass().
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var lost := DamagePipeline.apply_bypass(effect.value, ctx.player)
	if lost > 0:
		ctx.player.toll += lost
		ctx.player.took_damage_this_turn = true
		ctx.report_damage(ctx.player, lost, "self")
	# Bite Down's own self-damage-before-weapon-reflect timing gap (Phase 1
	# report, flagged item 1) would be handled here, right after the self
	# damage lands - out of scope this pass (no weapons at all yet).
