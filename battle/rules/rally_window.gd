extends RefCounted
class_name RallyWindow

# One recovery per discrete damage event (one per card played), not per
# hit within it - accumulates the largest single hit this window has
# seen and pays out only the delta when a new hit exceeds it, so "50% of
# the largest hit, not the sum" holds regardless of how many hits land
# in one card's resolution.

var max_hit: int = 0
var paid: int = 0

# Capped by whatever's left in the pool AT THE MOMENT OF THIS PAYOUT, not
# reserved up front - an intentional, kept quirk (see Combatant.rally_pool)
# from the old project: two windows racing for a small pool can starve
# each other, and that's accepted behavior, not a bug to fix here.
func contribute(player: Combatant, damage_to_hp: int) -> int:
	if damage_to_hp <= max_hit:
		return 0
	max_hit = damage_to_hp
	var target_total: int = max_hit * player.rally_recovery_percent / 100
	var additional: int = mini(target_total - paid, player.rally_pool)
	if additional <= 0:
		return 0
	player.rally_pool -= additional
	paid += additional
	player.hp = mini(player.hp + additional, player.max_hp)
	return additional
