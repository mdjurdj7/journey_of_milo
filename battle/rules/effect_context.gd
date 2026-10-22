extends RefCounted
class_name EffectContext

# What one CardEffect resolution needs to see and do - assembled fresh by
# battle_controller.gd for each card played, handed to whichever effect
# script resolves it (see effect_resolver.gd). Deliberately signal-free:
# effects report what happened by calling report_damage()/grace_reclaim()
# below, and battle_controller.gd decides what that becomes (a signal, a
# log call) - nothing under battle/rules/ knows signals exist.

var player: Combatant
var target: Combatant = null
# The enemies a card can reach: living and not buried (Combatant.buried).
# A buried enemy is left out, so an all-enemies effect never counts it.
var enemies: Array[Combatant] = []
var deck: Deck
# The cards the player chose from the hand for a GRANT_KEEP (Bide), picked
# before the play committed (BattleController's choose mode). Empty for
# every other card, and for a Bide played with none chosen.
var keep_choice: Array[CardData] = []
# The hand card the player chose for a COPY_HAND_CARD (Twice Over) to
# copy, picked before the play committed. Null for every other card.
var copy_choice: CardData = null
# The hand card a DEVOUR_FROM_HAND card (Take In) eats - the hand choice's
# one pick, as copy_choice is Twice Over's.
var devour_choice: CardData = null
# How many cards off the top of the draw pile the play shows once it has
# resolved (LOOK_AND_PLAY - Collateral's 3), for one to be played free; 0
# for none. Set by the effect, read by the controller after the play.
var look_count: int = 0
# What a Not So just undid (UndoLastAttackEffect): {"intent", "attacker",
# "restored", "dealt", "grace_closed"} - for the run log. Empty for any
# other card.
var last_undo: Dictionary = {}
# Cards committed this turn BEFORE the one this context is for - what
# Condition.FIRST_CARD_THIS_TURN reads. The controller counts a card at
# commit, so for the card resolving this is its count minus one; for a
# preview of a card still in hand it is the count itself.
var cards_played_before_this: int = 0
# The same count by tag (Combatant.tagged_plays_this_turn): tag -> cards
# carrying it committed this turn before this one - the resolving card's
# own tags taken back off, a hand card's preview the count itself. What
# CardEffect.repeat_per_earlier_play_tag reads (earlier_plays_tagged()).
var tagged_plays_before_this: Dictionary = {}
# The chain level as it stood before this card was played - what a Burst
# card reads (CardEffect.bonus_per_chain_level). For a preview of a card
# still in hand it is the level now. 0 with no chain.
var chain_level_before_this: int = 0
# The Energy the player held once this card's own cost was paid - what
# CardEffect.bonus_per_unspent_energy reads (Patient Cut). Set at the
# commit, and as a replay resolves; a card face in hand works its own out
# (CardBonus.unspent_energy_after()), so the shared preview leaves it 0.
var unspent_energy: int = 0
# The skillchain this card's play fired (Skillchain.step() at commit) and
# the chain level it fired at - resolved after the card's own effects
# (EffectResolver.resolve_card()). &"": none, and on any replay.
var skillchain: StringName = &""
var skillchain_level: int = 0
# Called with the amount reclaimed, so battle_controller.gd can mirror it
# onto RunState and tell the readouts. Grace itself is spent here, in the
# rules, the same way damage is dealt here and only REPORTED outward.
var on_grace_reclaimed: Callable = Callable()

# Whether the card being resolved is an ATTACK - set by EffectResolver.
# resolve_card(), and what take_attack_bonus() pays out on.
var card_is_attack: bool = false
# The card being resolved - set by EffectResolver.resolve_card() - for the
# weapon's self-loss bonus, which only the basic attack takes.
var resolving_card: CardData = null
# Whether this card's attack bonus has been handed out already - see
# take_attack_bonus(). Cleared per card by resolve_card().
var attack_bonus_taken: bool = false
# Whether this card has actually spent Toll (spend_toll()) - what hurries
# a countdown, once per card. Cleared per card by resolve_card().
var toll_spent_this_card: bool = false

# HP a card still in hand will have paid before its conditions are read -
# its own self-damage ahead of them, and the stance's per-Attack cost. Set
# only on a card face's preview copy (for_card_preview()); 0 when a card
# actually resolves, since by then those costs HAVE been paid. Read by
# Condition.CRITICAL and Condition.ENTERED_CRITICAL.
var preview_hp_cost: int = 0
# The player's HP as this card began resolving, before any of its HP
# costs (EffectResolver.resolve_card()) - what Condition.ENTERED_CRITICAL
# judges "before" by. -1 on a card face's preview copy, which reads the
# player's HP now instead (preview_hp_cost not yet paid).
var hp_at_card_start: int = -1

# Did this card's damage finish something off? Set by damage_effect.gd,
# cleared per card by EffectResolver.resolve_card(), read by
# Condition.TARGET_KILLED - the one condition that depends on what an
# earlier effect on the same card did rather than on state that already
# existed.
var killed_this_card: bool = false

# HP this card's hits took from enemies, net of Grace: each hit adds the
# HP the enemy actually lost (no overkill) less what Grace reclaimed from
# that hit, never below 0 (record_hit()). What an Attack Drains for while
# StatusData.attacks_drain is up (EffectResolver.resolve_card()). Cleared
# per card by resolve_card().
var hp_dealt_this_card: int = 0
# What this card's Attack-spent outgoing modifiers (Bent Nail's doubling)
# added to its blows, summed over every hit, before the enemy's own
# modifiers and Block (Status.attack_card_extra()). For the run log
# alone. Cleared per card by resolve_card().
var attack_card_extra_this_card: int = 0

# HP put back by a card (HEAL, TOLL_HEAL). The rules mutate the
# Combatant; this is how battle_controller.gd learns to mirror it onto
# the run's own HP and tell the readouts - the same split report_damage()
# already uses, and the same one Grace's reclaim uses.
var on_heal: Callable = Callable()

var on_damage: Callable = Callable()
# Called as on_damage.call(target_combatant, amount, kind) whenever an
# effect actually lands damage.

var on_block: Callable = Callable()
# Called as on_mound_broken.call(enemy, mound, own) when a hit breaks a
# mound of a dug-in enemy's row (EnemyTurn.break_mound()): `own` true for
# the one it was under - it is up, Exposed, and the hit's overkill follows
# as its own report_damage(). Before any later effect of the card.
var on_mound_broken: Callable = Callable()
# Called as on_block_gained.call(amount) when the player gains Block
# (gain_block()) - the view's number for it.
var on_block_gained: Callable = Callable()
# Called as on_replay.call() by a REPLAY_LAST_ATTACK (Second Swing): the
# view replays the last Attack itself once this card has resolved - its
# swing, impact and reports as a blow of their own (BattleController._
# replay_attack()). Unset (a bare rules context), the effect replays it
# on the spot (ReplayLastAttackEffect).
var on_replay: Callable = Callable()
# A card was Devoured by the keyword (DevourFromHandEffect): the hand's
# bite, nothing of the Devour button's. Called with the card.
var on_devour: Callable = Callable()
# This context is a replay's (Second Swing): the card resolving was
# played before, and isn't played now - nothing that waits for an Attack
# card is spent by it, and nothing doubles it (Bent Nail).
var is_replay: bool = false
# Called as on_extra_hit.call() before each further hit of a repeating
# hit (CardEffect.repeat_per_earlier_play_tag - Lash): what the card
# reports from then on is that hit's, which the view shows a beat after
# the one before. Nothing the rules decide reads it.
var on_extra_hit: Callable = Callable()
# Called as on_block.call(target_combatant, blocked, damage_to_hp) when a
# hit on an enemy meets its block - before that hit's on_damage, which
# only follows if some of it got through (damage_to_hp > 0).

# The attack bonus (AttackBonus) for the card being resolved, ONCE: the
# first damage effect to ask gets it, every later one 0 - the bonus is per
# Attack card, not per hit. Read when that effect resolves, so Critical
# is judged after whatever the card paid before it (Self-Eater's HP). 0 on
# anything but an ATTACK.
func take_attack_bonus() -> int:
	if not card_is_attack or attack_bonus_taken:
		return 0
	attack_bonus_taken = true
	var bonus: int = AttackBonus.for_player(player, player.hp) + player.take_self_loss_attack_bonus(resolving_card)
	# A charged bonus ("+3 on your next Attack") is spent by the card that
	# took it - whether or not the blow lands on anyone.
	Status.spend_attack_bonus_charges(player.statuses, player.is_critical())
	return bonus

# The attack bonus for a REPEATED hit of the card being resolved (Card
# Effect.repeat_per_earlier_play_tag - Lash): the ongoing part alone (Attack
# Bonus.ongoing_for_player()), every time it's asked - a one-shot charge
# went with the first hit, and spends nothing here. 0 on anything but an
# ATTACK.
func take_repeat_attack_bonus() -> int:
	if not card_is_attack:
		return 0
	return AttackBonus.ongoing_for_player(player, player.hp)

# Every Toll a card spends goes through here: at most what is held, so
# Toll never goes below 0, and anything spent at all marks the card as
# having spent Toll (toll_spent_this_card - Sentence's hurry, once per
# card however much). Returns what was actually spent. Gaining Toll, or
# losing it any other way (the floor's reset), never comes here.
func spend_toll(amount: int) -> int:
	var spent: int = clampi(amount, 0, maxi(player.toll, 0))
	if spent <= 0:
		return 0
	player.toll -= spent
	player.toll_spent_this_fight += spent
	toll_spent_this_card = true
	player.toll_spent_this_turn = true
	return spent

# Every Block the player gains goes through here, so a stance that
# forbids it (Last Resort, while Critical - read live, here) is asked in
# one place. Returns what was gained.
func gain_block(amount: int) -> int:
	if amount <= 0 or Stance.prevents_block_gain(player.stance, player.is_critical()):
		return 0
	player.block += amount
	RunLogger.block_gained(amount)
	if on_block_gained.is_valid():
		on_block_gained.call(amount)
	return amount

# This context for reading one card still in hand whose costs come to
# `hp_cost` - a copy, so the hand's shared context is never touched.
func for_card_preview(hp_cost: int) -> EffectContext:
	var copy := EffectContext.new()
	copy.player = player
	copy.target = target
	copy.enemies = enemies
	copy.deck = deck
	copy.cards_played_before_this = cards_played_before_this
	copy.tagged_plays_before_this = tagged_plays_before_this
	copy.chain_level_before_this = chain_level_before_this
	copy.preview_hp_cost = hp_cost
	return copy

# Cards carrying `tag` played this turn before this one.
func earlier_plays_tagged(tag: StringName) -> int:
	return int(tagged_plays_before_this.get(tag, 0))

func report_damage(target_combatant: Combatant, amount: int, kind: String) -> void:
	if on_damage.is_valid():
		on_damage.call(target_combatant, amount, kind)
	if target_combatant != null and target_combatant.mound_owner != null and target_combatant.hp <= 0:
		_break_mound(target_combatant, kind)

# A mound's Combatant brought to 0 (report_damage()): the mound breaks. Its
# own: the enemy up and Exposed, the rest of the card landing on it
# (landing_for()), and the hit's overkill carried into it raw - past its
# block, but not through its statuses - as damage of its own. A wrong one:
# gone, the rest of the card's single-target effects landing on nothing.
func _break_mound(guard: Combatant, kind: String) -> void:
	var owner: Combatant = guard.mound_owner
	var outcome: EnemyTurn.MoundBreak = EnemyTurn.break_mound(owner, owner_data(owner), guard.mound_index)
	if outcome == EnemyTurn.MoundBreak.NOT_BROKEN:
		return
	var own: bool = outcome == EnemyTurn.MoundBreak.BROKE_TRUE
	if on_mound_broken.is_valid():
		on_mound_broken.call(owner, guard.mound_index, own)
	if target == guard:
		target = owner if own else null
	if not own:
		return
	var overkill: int = guard.last_overkill
	guard.last_overkill = 0
	if overkill <= 0 or owner.hp <= 0:
		return
	var result := DamagePipeline.resolve(overkill, owner)
	report_block(owner, result)
	if result["damage_to_hp"] > 0:
		if owner.hp <= 0:
			killed_this_card = true
		report_damage(owner, result["damage_to_hp"], kind)

# The EnemyData behind a dug-in enemy, for EnemyTurn's rules on its
# mounds - handed in by the controller (mound_data), keyed by Combatant.
var mound_data: Dictionary = {}
func owner_data(owner: Combatant) -> EnemyData:
	return mound_data.get(owner) as EnemyData

# Where a hit meant for `combatant` lands now: itself, or - for a mound's
# Combatant - itself while the mound stands, the enemy under it once its
# own mound is broken (it is up), nothing once a wrong one is gone or the
# row has gone.
func landing_for(combatant: Combatant) -> Combatant:
	if combatant == null or combatant.mound_owner == null:
		return combatant
	if EnemyTurn.mound_standing(combatant):
		return combatant
	var owner: Combatant = combatant.mound_owner
	if not owner.dug_in and combatant.mound_index == owner.true_mound and combatant.hp <= 0:
		return owner
	return null

# What a status aimed at the card's target lands on: the target, or - a
# mound - the enemy under it (Brace, Deny, Sentence at a mound
# reach the Siltjaw and break nothing).
func status_target() -> Combatant:
	if target != null and target.mound_owner != null:
		return target.mound_owner
	return target

# The enemies in reach as holders of statuses: each of `enemies`, with a
# mound's Combatant standing for the enemy under it, once.
func status_holders() -> Array[Combatant]:
	var holders: Array[Combatant] = []
	for enemy in enemies:
		var holder: Combatant = enemy.mound_owner if enemy.mound_owner != null else enemy
		if not holders.has(holder):
			holders.append(holder)
	return holders

# A hit on an enemy's DamagePipeline result: tells on_block if its block
# took any of it. Call before that hit's report_damage().
func report_block(target_combatant: Combatant, result: Dictionary) -> void:
	var blocked: int = result["blocked"]
	if blocked > 0 and on_block.is_valid():
		on_block.call(target_combatant, blocked, int(result["damage_to_hp"]))

# Damage this player just dealt takes Grace back 1:1, per hit as it
# lands, never past max HP and never more Grace than is left. Silent and
# free when the player has none open, which is every fight for a class
# without the passive.
# HP a card costs before its effects: the stance's per-Attack price.
# Self-inflicted, so it takes the same route SELF_DAMAGE does: past block
# and absorb, accruing Toll, reported as "self" - and opening no Grace,
# because Grace only ever opens on an enemy's hit.
# `source` names what the price is paid to, for the run log ("stance:
# <id>"); the Toll it accrues is put down to it too.
func pay_upfront_hp_cost(amount: int, source: String = "") -> void:
	if amount <= 0:
		return
	if not source.is_empty():
		RunLogger.push_source(source)
	var lost: int = DamagePipeline.apply_bypass(amount, player)
	if lost > 0:
		player.gain_self_loss_toll(lost)
		player.took_damage_this_turn = true
		# The price, split out of the "self" loss for the run log.
		RunLogger.hp_cost_paid(lost)
		report_damage(player, lost, "self")
	if not source.is_empty():
		RunLogger.pop_source()

# The Drain a self-loss counter has handed over (Combatant.pending_
# drain), resolved now, as one Drain from every enemy in reach - called
# right after anything that can lose the player HP to their own effect.
# Never on a dead player: a loss that killed them is not undone by the
# counter it completed. What it kills leaves `enemies`, and `target` when
# it was the target, so the rest of the card doesn't strike a body.
func resolve_pending_drain() -> void:
	var amount: int = player.pending_drain
	player.pending_drain = 0
	if amount <= 0 or player.hp <= 0:
		return
	if not DrainEffect.drain(amount, enemies, self):
		return
	var living: Array[Combatant] = []
	for enemy in enemies:
		if enemy.hp > 0:
			living.append(enemy)
	enemies = living
	if target != null and target.hp <= 0:
		target = null

# Heals the player and reports it. Callers mutate through this rather
# than touching hp directly, so the run's HP can't drift from the
# fight's - it silently did for HEAL before this existed.
func heal(amount: int) -> void:
	if amount <= 0:
		return
	var before: int = player.hp
	player.hp = mini(player.hp + amount, player.max_hp)
	var gained: int = player.hp - before
	if gained > 0 and on_heal.is_valid():
		on_heal.call(gained)

# Returns what it reclaimed, so a Drain on the same hit (record_hit())
# heals only the rest.
func grace_reclaim(damage_to_hp: int) -> int:
	if damage_to_hp <= 0 or player.grace <= 0:
		return 0
	var reclaimed: int = mini(damage_to_hp, player.grace)
	reclaimed = mini(reclaimed, player.max_hp - player.hp)
	if reclaimed <= 0:
		return 0
	player.grace -= reclaimed
	player.hp += reclaimed
	if on_grace_reclaimed.is_valid():
		on_grace_reclaimed.call(reclaimed)
	return reclaimed

# One hit of this card's has landed: `hp_lost` is the HP the enemy
# actually lost (its HP before less after - no overkill), `reclaimed`
# what Grace took back from that same hit. Adds the remainder to
# hp_dealt_this_card - so Grace and an Attack's Drain never both heal
# for the same point of damage.
func record_hit(hp_lost: int, reclaimed: int) -> void:
	hp_dealt_this_card += maxi(hp_lost - reclaimed, 0)
