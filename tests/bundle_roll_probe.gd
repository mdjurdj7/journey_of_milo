extends SceneTree

# Headless probe for the belongings rolls, in two parts.
#
# The bundle: no floor carries a BundleProp since floor 2's island bundle
# became the trough, so this instances bundle_prop.tscn directly and
# gives it what that placement gave it - the belongings pool, floor 2's
# gold range and rare pool - then rolls it once per seed for SEED_COUNT
# seeds, with the arguments RegionField._setup_bundle() passes. Asserts
# the split is near 80/15/5, that gold stays inside the floor's range x
# the bundle's multiplier, and that every card comes from the pool it
# should.
#
# The cache: loads floor 2's own FloorData, finds its alcove cache
# (BelongingsCache), instantiates that scene the way RegionField does
# (overrides applied, never added to the tree) and rolls it once per seed,
# with the arguments RegionField._setup_belongings_cache() passes. Asserts
# the case holds 45 gold, that the pack's card is always there and from
# the pool, and that Glassbone comes up near glassbone_chance, spread
# evenly over the three. Then draws the bedroll's keepsake once per seed
# as the screen would (roll_keepsake()), with the slot empty and with
# Bent Nail held: always one, always from the table, never the one held,
# the rest near equal.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/bundle_roll_probe.gd
#
# Exit code 0 = passed, 1 = a failure (each printed as FAIL). In the game
# the roll draws from RunState.rng in the floor's spawn order, after
# whatever the props before it drew; a fresh generator per seed here
# samples the same distribution.
#
# Untyped against the project's own classes (get()/call() only), for the
# reason kill_order_probe.gd gives.

const FLOOR_PATH := "res://floors/region1_floor2.tres"
const BUNDLE_SCENE_PATH := "res://field/bundle_prop.tscn"
# What floor 2's island bundle drew from before it became the trough.
const BUNDLE_POOL_PATH := "res://cards/pools/belongings_pool.tres"
const CACHE_SCENE_PATH := "res://field/belongings_cache.tscn"
const BENT_NAIL_PATH := "res://run/keepsakes/bent_nail.tres"
const SEED_COUNT := 10000
# About four standard deviations at 10,000 rolls.
const SHARE_TOLERANCE := {"gold": 0.017, "card": 0.015, "rare": 0.009}
const EXPECTED_SHARE := {"gold": 0.80, "card": 0.15, "rare": 0.05}
# The same, for a 25% share of 10,000, a third of the ~2,500 Glassbone
# rolls, and a quarter or a third of 10,000.
const GLASSBONE_TOLERANCE := 0.017
const GLASSBONE_SLOT_TOLERANCE := 0.038
const KEEPSAKE_TOLERANCE := 0.019

var _failures: int = 0

func _initialize() -> void:
	var floor_data: Resource = load(FLOOR_PATH)
	_probe_bundle(floor_data)
	_probe_cache(floor_data)
	_finish()

func _probe_bundle(floor_data: Resource) -> void:
	var bundle: Node = (load(BUNDLE_SCENE_PATH) as PackedScene).instantiate()
	var pool: Resource = load(BUNDLE_POOL_PATH)
	var rare_pool: Resource = floor_data.get("rare_pool")
	var rare_source: Resource = rare_pool if rare_pool != null and not (rare_pool.get("entries") as Array).is_empty() else pool
	var gold_min: int = floor_data.get("gold_min")
	var gold_max: int = floor_data.get("gold_max")
	var multiplier: float = bundle.get("gold_multiplier")
	var lowest: int = maxi(roundi(float(mini(gold_min, gold_max)) * multiplier), 1)
	var highest: int = maxi(roundi(float(maxi(gold_min, gold_max)) * multiplier), 1)
	print("bundle (instanced): pool %s, rare pool %s, gold %d..%d x %.2f -> %d..%d" % [pool.resource_path, "none (falls back)" if rare_source == pool else rare_pool.resource_path, gold_min, gold_max, multiplier, lowest, highest])

	var counts := {"gold": 0, "card": 0, "rare": 0}
	var gold_seen_min: int = 1 << 30
	var gold_seen_max: int = 0
	var rng := RandomNumberGenerator.new()
	for seed_value in SEED_COUNT:
		rng.seed = seed_value
		bundle.call("roll", rng, gold_min, gold_max, pool, rare_pool)
		var kind: int = bundle.get("contents")
		var card: Resource = bundle.get("contents_card")
		match kind:
			1:
				counts["gold"] += 1
				var amount: int = bundle.get("contents_gold")
				gold_seen_min = mini(gold_seen_min, amount)
				gold_seen_max = maxi(gold_seen_max, amount)
				if amount < lowest or amount > highest:
					_fail("bundle seed %d: %d gold, outside %d..%d" % [seed_value, amount, lowest, highest])
			2:
				counts["card"] += 1
				if not (pool.get("entries") as Array).has(card):
					_fail("bundle seed %d: card '%s' is not in the bundle's pool" % [seed_value, card.resource_path])
			3:
				counts["rare"] += 1
				if not (rare_source.get("entries") as Array).has(card):
					_fail("bundle seed %d: rare card '%s' is not in the rare source" % [seed_value, card.resource_path])
			_:
				_fail("bundle seed %d: the bundle rolled nothing" % seed_value)
	bundle.free()

	for kind: String in ["gold", "card", "rare"]:
		var share: float = float(counts[kind]) / float(SEED_COUNT)
		var ok: bool = absf(share - EXPECTED_SHARE[kind]) <= SHARE_TOLERANCE[kind]
		print("  %-4s %5d  %5.2f%%  (expected %.0f%% +/- %.1f)%s" % [kind, counts[kind], share * 100.0, EXPECTED_SHARE[kind] * 100.0, SHARE_TOLERANCE[kind] * 100.0, "" if ok else "  <- FAIL"])
		if not ok:
			_failures += 1
	print("  gold seen %d..%d" % [gold_seen_min, gold_seen_max])

func _probe_cache(floor_data: Resource) -> void:
	var entry: Resource = null
	for prop: Resource in floor_data.get("props"):
		var scene: PackedScene = prop.get("scene")
		if scene != null and scene.resource_path == CACHE_SCENE_PATH:
			entry = prop
			break
	if entry == null:
		_fail("floor 2 has no belongings cache prop")
		return

	var cache: Node = (entry.get("scene") as PackedScene).instantiate()
	var overrides: Dictionary = entry.get("overrides")
	for key: String in overrides:
		cache.set(key, overrides[key])
	var pool: Resource = entry.get("pool") if entry.get("pool") != null else floor_data.get("reward_pool")
	var coin_amount: int = cache.get("coin_amount")
	var glassbone_chance: float = cache.get("glassbone_chance")
	var table: Resource = cache.get("keepsake_table")
	if table == null:
		_fail("the cache has no keepsake_table")
		cache.free()
		return
	var trinkets: Array = []
	for keepsake_entry: Resource in table.get("entries"):
		trinkets.append(keepsake_entry.get("trinket"))
	print("cache at %s: case %d gold, pack from %s, bedroll from %s (%d keepsakes), Glassbone %.0f%%" % [entry.get("position"), coin_amount, pool.resource_path, table.resource_path, trinkets.size(), glassbone_chance * 100.0])
	if coin_amount != 45:
		_fail("the case holds %d gold, not 45" % coin_amount)

	# The roll at floor load: the pack's card and the Glassbone.
	var glassbone_rolls: int = 0
	var glassbone_by_slot: Array[int] = [0, 0, 0]
	var rng := RandomNumberGenerator.new()
	for seed_value in SEED_COUNT:
		rng.seed = seed_value
		cache.call("roll", rng, pool)
		var card: Resource = cache.get("card")
		if card == null:
			_fail("cache seed %d: the pack's card rolled nothing" % seed_value)
		elif not (pool.get("entries") as Array).has(card):
			_fail("cache seed %d: card '%s' is not in the cache's pool" % [seed_value, card.resource_path])
		var slot: int = cache.get("glassbone_slot")
		if slot >= 0:
			if slot > 2:
				_fail("cache seed %d: Glassbone in column %d" % [seed_value, slot])
				continue
			glassbone_rolls += 1
			glassbone_by_slot[slot] += 1
	_expect_share("Glassbone", glassbone_rolls, SEED_COUNT, glassbone_chance, GLASSBONE_TOLERANCE)
	for slot in 3:
		_expect_share("  in column %d" % slot, glassbone_by_slot[slot], glassbone_rolls, 1.0 / 3.0, GLASSBONE_SLOT_TOLERANCE)

	# The bedroll's draw as the screen opens: the slot empty, then held.
	var offered: Array[StringName] = []
	for equipped: Resource in [null, load(BENT_NAIL_PATH)]:
		var counts: Dictionary = {}
		for trinket: Resource in trinkets:
			counts[trinket] = 0
		for seed_value in SEED_COUNT:
			rng.seed = seed_value
			cache.call("roll_keepsake", rng, equipped, offered)
			var keepsake: Resource = cache.get("keepsake")
			if keepsake == null:
				_fail("cache seed %d: the bedroll's keepsake rolled nothing" % seed_value)
			elif not counts.has(keepsake):
				_fail("cache seed %d: keepsake '%s' is not in the table" % [seed_value, keepsake.resource_path])
			elif keepsake == equipped:
				_fail("cache seed %d: the bedroll holds the keepsake already held" % seed_value)
			else:
				counts[keepsake] += 1
		var drawable: int = trinkets.size() - (1 if trinkets.has(equipped) else 0)
		print("  held: %s" % (equipped.get("display_name") if equipped != null else "nothing"))
		for trinket: Resource in trinkets:
			var expected: float = 0.0 if trinket == equipped else 1.0 / float(drawable)
			_expect_share("    %s" % trinket.get("display_name"), counts[trinket], SEED_COUNT, expected, KEEPSAKE_TOLERANCE)
	cache.free()

# One share against its expectation, printed, a failure past tolerance.
func _expect_share(label: String, count: int, total: int, expected: float, tolerance: float) -> void:
	var share: float = float(count) / float(maxi(total, 1))
	var ok: bool = absf(share - expected) <= tolerance
	print("  %-22s %5d  %5.2f%%  (expected %.1f%% +/- %.1f)%s" % [label, count, share * 100.0, expected * 100.0, tolerance * 100.0, "" if ok else "  <- FAIL"])
	if not ok:
		_failures += 1

func _fail(message: String) -> void:
	_failures += 1
	if _failures <= 20:
		print("FAIL: ", message)

func _finish() -> void:
	print("\nbundle_roll_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)
