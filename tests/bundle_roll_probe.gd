extends SceneTree

# Headless probe for the bundle's roll. Loads floor 2's own FloorData,
# finds its bundle prop, instantiates that scene the way RegionField does
# (overrides applied, never added to the tree) and rolls it once per seed
# for SEED_COUNT seeds, with the same arguments RegionField._setup_
# bundle() passes. Asserts the split is near 80/15/5, that gold stays
# inside the floor's range x the bundle's multiplier, and that every card
# comes from the pool it should.
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
const SEED_COUNT := 10000
# About four standard deviations at 10,000 rolls.
const SHARE_TOLERANCE := {"gold": 0.017, "card": 0.015, "rare": 0.009}
const EXPECTED_SHARE := {"gold": 0.80, "card": 0.15, "rare": 0.05}

var _failures: int = 0

func _initialize() -> void:
	var floor_data: Resource = load(FLOOR_PATH)
	var entry: Resource = null
	for prop: Resource in floor_data.get("props"):
		var scene: PackedScene = prop.get("scene")
		if scene != null and scene.resource_path == BUNDLE_SCENE_PATH:
			entry = prop
			break
	if entry == null:
		_fail("floor 2 has no bundle prop")
		_finish()
		return

	var bundle: Node = (entry.get("scene") as PackedScene).instantiate()
	var overrides: Dictionary = entry.get("overrides")
	for key: String in overrides:
		bundle.set(key, overrides[key])
	var pool: Resource = entry.get("pool") if entry.get("pool") != null else floor_data.get("reward_pool")
	var rare_pool: Resource = floor_data.get("rare_pool")
	var rare_source: Resource = rare_pool if rare_pool != null and not (rare_pool.get("entries") as Array).is_empty() else pool
	var gold_min: int = floor_data.get("gold_min")
	var gold_max: int = floor_data.get("gold_max")
	var multiplier: float = bundle.get("gold_multiplier")
	var lowest: int = maxi(roundi(float(mini(gold_min, gold_max)) * multiplier), 1)
	var highest: int = maxi(roundi(float(maxi(gold_min, gold_max)) * multiplier), 1)
	print("bundle at %s: pool %s, rare pool %s, gold %d..%d x %.2f -> %d..%d" % [entry.get("position"), pool.resource_path, "none (falls back)" if rare_source == pool else rare_pool.resource_path, gold_min, gold_max, multiplier, lowest, highest])

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
					_fail("seed %d: %d gold, outside %d..%d" % [seed_value, amount, lowest, highest])
			2:
				counts["card"] += 1
				if not (pool.get("entries") as Array).has(card):
					_fail("seed %d: card '%s' is not in the bundle's pool" % [seed_value, card.resource_path])
			3:
				counts["rare"] += 1
				if not (rare_source.get("entries") as Array).has(card):
					_fail("seed %d: rare card '%s' is not in the rare source" % [seed_value, card.resource_path])
			_:
				_fail("seed %d: the bundle rolled nothing" % seed_value)
	bundle.free()

	for kind: String in ["gold", "card", "rare"]:
		var share: float = float(counts[kind]) / float(SEED_COUNT)
		var ok: bool = absf(share - EXPECTED_SHARE[kind]) <= SHARE_TOLERANCE[kind]
		print("  %-4s %5d  %5.2f%%  (expected %.0f%% +/- %.1f)%s" % [kind, counts[kind], share * 100.0, EXPECTED_SHARE[kind] * 100.0, SHARE_TOLERANCE[kind] * 100.0, "" if ok else "  <- FAIL"])
		if not ok:
			_failures += 1
	print("  gold seen %d..%d" % [gold_seen_min, gold_seen_max])
	_finish()

func _fail(message: String) -> void:
	_failures += 1
	if _failures <= 20:
		print("FAIL: ", message)

func _finish() -> void:
	print("\nbundle_roll_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)
