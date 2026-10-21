extends RefCounted
class_name TakeFromAttackEffect

# Wrest: up to `value` off the target's queued attack, and as much Block.
# What it takes is read off that attack's landing total as it stands now
# (EnemyTurn.preview_intent() - after any Brace or Garnish already on it,
# and the player's own Unbroken); less when the attack is smaller. It goes
# on as `status_data` - an intent mark that reduces the attack's total
# (Wrested), soaked hit by hit as Garnish's is - at that amount, bound to
# the intent as ApplyStatusToTargetEffect binds Brace's and Garnish's;
# then the Block, through the Block a card gives (a stance that forbids it
# gives none). The Block stays whatever later changes the attack: it is
# what Wrest took when played.
#
# An intent carried out twice (Bereft): the mark cuts the first action -
# the one it was put on - and is spent there; the second lands in full
# (Status.marks()). So what Wrest takes is read off the first
# action, and the Block is given once.
func resolve(effect: CardEffect, ctx: EffectContext) -> void:
	var target: Combatant = ctx.status_target()
	if effect.status_data == null or target == null or target.enemy_data == null:
		return
	var taken: int = mini(maxi(effect.value, 0), landing_total(target, ctx.player))
	if taken <= 0:
		return
	Status.apply_to(target.statuses, effect.status_data)
	var applied: Status = Status.find_in(target.statuses, effect.status_data)
	if applied != null:
		applied.magnitude = taken
		applied.bound_intent = EnemyTurn.current_intent(target, target.enemy_data)
	ctx.gain_block(taken)

# What `target`'s queued attack lands on `player` now - its first action's
# hits, after every mark and reduction already on it. 0 for no attack.
static func landing_total(target: Combatant, player: Combatant) -> int:
	var intent: EnemyIntent = EnemyTurn.current_intent(target, target.enemy_data)
	if intent == null or intent.type != EnemyIntent.IntentType.ATTACK:
		return 0
	var preview: Dictionary = EnemyTurn.preview_intent(target, target.enemy_data, player)
	var amounts: Array = preview.get("hit_amounts", [])
	var hits: int = mini(EnemyTurn.hit_count(target, intent), amounts.size())
	var total: int = 0
	for i in hits:
		total += int(amounts[i])
	return total
