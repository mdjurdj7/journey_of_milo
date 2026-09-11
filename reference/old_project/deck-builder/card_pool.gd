extends RefCounted
class_name CardPool
# Shared "read this run's class card pool off disk" helper - reward_
# screen.gd's regular/rare card rolls and RoomState's shop stock roll
# both need the exact same folder-scan logic (see character_data.gd's
# card_pool_folder), so it lives here once instead of copied into both -
# same "one small RefCounted helper" shape as EnemyPool/EncounterPool/
# WeightedRandom.

static func load_class_pool(character: CharacterData = null) -> Array[CardData]:
	var pool: Array[CardData] = []
	# null (every existing caller - reward_screen.gd's rolls, RoomState's
	# shop stock) keeps reading whichever class the CURRENT RUN is
	# playing, exactly as before this param existed. An explicit character
	# (card_glossary.gd's own use - see its header) loads THAT character's
	# pool instead, without touching RunState.current_class - browsing a
	# pool for reference shouldn't change what the active run thinks it's
	# playing.
	var target_character: CharacterData = character if character != null else RunState.current_class
	var folder := target_character.card_pool_folder
	var dir := DirAccess.open(folder)
	# DirAccess.open() returns null (instead of raising an error) when the
	# folder doesn't exist - calling a method on that null, as if it were
	# a real DirAccess, would crash whichever caller triggered this.
	# Missing reward content is a real possibility (an empty/not-yet-
	# populated pool), not a bug that should take the whole game down
	# with it, so this checks for null and bails out to an empty pool.
	if dir == null:
		push_error("Reward card pool folder not found: %s" % folder)
		return pool
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			pool.append(load(folder + file_name))
	return pool

# Rolls ONE rarity-weighted card out of `pool` - extracted (2026-08-29,
# three-chest treasure room) out of reward_screen.gd's own private _roll_
# rarity()/_pick_card_by_rarity(), which is now just a thin caller of
# this - so a second call site (field_chest.gd's Chest B, via field_
# room.gd's own _on_chest_card_offered()) can draw "one card, the same
# way the post-battle screen would" without a second, separately-tuned
# copy of the weighting. Uses WeightedRandom (see weighted_random.gd) the
# same way reward_screen.gd's own roll always has - only COMMON/RARE are
# ever rolled here, matching that screen's regular card-choice roll
# exactly; ULTRA_RARE/SECRET_RARE have their own separate, independent
# rolls elsewhere (reward_screen.gd's own _roll_rare_drop()), untouched
# by this. Steps down one rarity tier at a time if the rolled tier has
# nothing in `pool` (COMMON is the floor) - always returns something as
# long as `pool` has at least one COMMON card, same guarantee the
# original private version made.
static func pick_weighted_card(pool: Array[CardData], common_weight: float, rare_weight: float) -> CardData:
	var rarity: CardData.Rarity = WeightedRandom.pick({
		CardData.Rarity.COMMON: common_weight,
		CardData.Rarity.RARE: rare_weight,
	})
	while rarity >= CardData.Rarity.COMMON:
		var matches: Array = pool.filter(func(card): return card.rarity == rarity)
		if not matches.is_empty():
			return matches.pick_random()
		rarity -= 1
	return pool.pick_random()
