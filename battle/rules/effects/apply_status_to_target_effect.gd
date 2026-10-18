extends RefCounted
class_name ApplyStatusToTargetEffect

# One that marks an intent (StatusData.intent_mark - Brace, Garnish) is
# bound to the intent its enemy has queued as it lands (Status.bound_
# intent).
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var target: Combatant = ctx.status_target()
	if effect.status_data == null or target == null:
		return
	Status.apply_to(target.statuses, effect.status_data)
	if effect.status_data.intent_mark != &"":
		var applied: Status = Status.find_in(target.statuses, effect.status_data)
		if applied != null:
			applied.bound_intent = EnemyTurn.current_intent(target, target.enemy_data) if target.enemy_data != null else null
