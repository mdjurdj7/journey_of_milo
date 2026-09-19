extends RefCounted
class_name ApplyStanceEffect

# Takes the stance, or deepens it if it's the one already held - see
# Stance.apply_to(), which owns that decision. A stance card played while
# a DIFFERENT stance is up replaces it: one bargain at a time.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	if effect.stance_data == null:
		return
	Stance.apply_to(ctx.player, effect.stance_data)
