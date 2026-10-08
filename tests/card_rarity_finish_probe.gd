extends SceneTree

# Headless probe for the card name's rarity finish (CardRarityFinish,
# battle/card_rarity_finish.tres, card_name_finish.gdshader):
#
#   - each tier maps to its finish: Common flat ink and no material,
#     Uncommon pewter, Rare dark gold, Ultra Rare dark gold with the
#     three-hue band; every base at least min_contrast (4.5:1) on bone
#   - a CardView of each tier wears it: no material on a Common name,
#     its own ShaderMaterial with the tier's base on the others, at rest
#   - the sheen plays exactly once per trigger - play_name_sheen(), a hover
#     start - and goes back to rest (sheen_t -1, no tween) without looping;
#     a hover held, or a Common name, plays nothing
#   - every tempered card ("Slash+") wears its original's finish
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/card_rarity_finish_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# No Ultra Rare card exists yet: the probe makes one in memory from a
# Rare.

const CASES := 4
const FINISH_PATH := "res://battle/card_rarity_finish.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const CARDS_DIR := "res://cards/data"
const TEMPERED_DIR := "res://cards/tempered"
# Short, so the probe waits a beat, not 0.9 s, per sweep.
const PROBE_SHEEN_SEC := 0.3
const SAFETY_SECONDS := 60.0

var _finish: CardRarityFinish = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	# A CardView added before the tree's first frame doesn't ready.
	await process_frame
	_finish = load(FINISH_PATH) as CardRarityFinish
	if _finish == null:
		_fail("The finish resource loads (%s)" % FINISH_PATH)
	else:
		_check_tiers()
		await _check_card_views()
		await _check_sheen()
		await _check_tempered()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("card_rarity_finish_probe: PASSED")
		quit(0)
	else:
		print("card_rarity_finish_probe: %d FAILED" % _failures)
		quit(1)

# The tiers as the brief sets them, and every base legible on bone.
func _check_tiers() -> void:
	var expected: Dictionary = {
		CardData.CardRarity.COMMON: [Color(0.165, 0.165, 0.18), false, false, "COMMON", true],
		CardData.CardRarity.UNCOMMON: [Color(0.29, 0.31, 0.34), true, false, "UNCOMMON", true],
		CardData.CardRarity.RARE: [Color(0.42, 0.33, 0.13), true, false, "RARE", false],
		CardData.CardRarity.ULTRA_RARE: [Color(0.42, 0.33, 0.13), true, true, "ULTRA RARE", false],
	}
	for rarity: CardData.CardRarity in expected:
		var row: Array = expected[rarity]
		var tier: String = row[3]
		_expect(_finish.base_color(rarity).is_equal_approx(row[0]), "%s's base is %s (got %s)" % [tier, row[0], _finish.base_color(rarity)])
		_expect_eq(_finish.has_finish(rarity), row[1], "...%s wears a finish: %s" % [tier, row[1]])
		_expect_eq(_finish.is_rainbow(rarity), row[2], "...its sheen is the three hues: %s" % row[2])
		_expect_eq(_finish.tier_label_text(rarity), tier, "...it is named %s" % tier)
		_expect_eq(_finish.tier_label_dimmed(rarity), row[4], "...in %s bone" % ("dim" if row[4] else "full"))
		var ratio: float = CardRarityFinish.contrast_ratio(_finish.base_color(rarity), _finish.bone)
		print("card_rarity_finish_probe: %s base %.2f:1 on bone" % [tier, ratio])
		_expect(ratio >= _finish.min_contrast, "...its base holds %.1f:1 on bone (got %.2f:1)" % [_finish.min_contrast, ratio])
	_expect(_finish.uncommon_highlight.is_equal_approx(Color(0.55, 0.58, 0.61)), "Uncommon's sheen is pewter (0.55, 0.58, 0.61)")
	_expect(_finish.rare_highlight.is_equal_approx(Color(0.69, 0.56, 0.27)), "Rare's sheen is gold (0.69, 0.56, 0.27)")
	_expect(_finish.ultra_hue_rose.is_equal_approx(Color(0.55, 0.44, 0.50)) and _finish.ultra_hue_teal.is_equal_approx(Color(0.37, 0.49, 0.53)) and _finish.ultra_hue_olive.is_equal_approx(Color(0.54, 0.54, 0.32)), "Ultra Rare's band is rose, teal and olive")
	_expect_eq(_finish.tier_label_text(CardData.CardRarity.UNSET), "", "An untagged card names no tier")
	_completed += 1

# A CardView of each tier: the material, and what it carries at rest.
func _check_card_views() -> void:
	for rarity: CardData.CardRarity in CardData.rarity_tiers():
		var card: CardData = _card_of(rarity)
		if card == null:
			_fail("A card of rarity %d to show" % rarity)
			continue
		var view: CardView = await _view(card)
		var material: ShaderMaterial = view.get_name_finish()
		var tier: String = _finish.tier_label_text(rarity)
		if not _finish.has_finish(rarity):
			_expect(material == null, "%s (%s): no material on the name" % [card.card_name, tier])
			_expect_eq(view.name_label.get_theme_color("font_color"), _finish.common_ink, "...the name in flat ink")
		else:
			_expect(material != null, "%s (%s): its name wears the finish" % [card.card_name, tier])
			if material != null:
				_expect((material.get_shader_parameter("base_color") as Color).is_equal_approx(_finish.base_color(rarity)), "...in its tier's base")
				_expect((material.get_shader_parameter("highlight_color") as Color).is_equal_approx(_finish.highlight_color(rarity)), "...toward its tier's highlight")
				_expect_eq(bool(material.get_shader_parameter("rainbow")), _finish.is_rainbow(rarity), "...rainbow: %s" % _finish.is_rainbow(rarity))
				_expect_eq(float(material.get_shader_parameter("sheen_t")), -1.0, "...at rest, no band")
				_expect(float(material.get_shader_parameter("text_width_px")) > 0.0, "...its gradient spanning the name's width")
		_expect(not view.is_name_sheen_playing(), "...nothing playing at rest")
		_expect_eq(view.get_name_sheens_started(), 0, "...and no sheen started")
		view.queue_free()
	_completed += 1

# One sweep per trigger, back to rest after, never looping; a held hover
# and a Common name play nothing.
func _check_sheen() -> void:
	var saved: float = _finish.sheen_duration_sec
	_finish.sheen_duration_sec = PROBE_SHEEN_SEC
	var view: CardView = await _view(_card_of(CardData.CardRarity.RARE))
	var material: ShaderMaterial = view.get_name_finish()
	view.play_name_sheen()
	_expect_eq(view.get_name_sheens_started(), 1, "play_name_sheen() starts one sweep")
	_expect(view.is_name_sheen_playing(), "...running")
	await create_timer(PROBE_SHEEN_SEC * 0.5).timeout
	var mid: float = float(material.get_shader_parameter("sheen_t"))
	_expect(mid > 0.0 and mid < 1.0, "...the band part way across mid-sweep (sheen_t %.2f)" % mid)
	await create_timer(PROBE_SHEEN_SEC + 0.3).timeout
	_expect(not view.is_name_sheen_playing(), "...over after sheen_duration_sec")
	_expect_eq(float(material.get_shader_parameter("sheen_t")), -1.0, "...back at rest")
	await create_timer(PROBE_SHEEN_SEC * 2.0).timeout
	_expect_eq(view.get_name_sheens_started(), 1, "...and it never loops")
	_expect_eq(float(material.get_shader_parameter("sheen_t")), -1.0, "...still at rest")

	view.set_hovered(true)
	_expect_eq(view.get_name_sheens_started(), 2, "A hover start plays one")
	view.set_hovered(true)
	_expect_eq(view.get_name_sheens_started(), 2, "...a hover held plays no second")
	view.set_hovered(false)
	view.set_hovered(true)
	_expect_eq(view.get_name_sheens_started(), 3, "...a fresh hover plays one more")
	view.play_name_sheen()
	_expect_eq(view.get_name_sheens_started(), 4, "A trigger mid-sweep restarts it")
	await create_timer(PROBE_SHEEN_SEC + 0.3).timeout
	_expect(not view.is_name_sheen_playing(), "...one sweep, then rest")
	view.queue_free()

	var common: CardView = await _view(_card_of(CardData.CardRarity.COMMON))
	common.set_hovered(true)
	common.play_name_sheen()
	_expect_eq(common.get_name_sheens_started(), 0, "A Common name has no sheen to play")
	common.queue_free()
	_finish.sheen_duration_sec = saved
	_completed += 1

# Every tempered card wears what its original wears.
func _check_tempered() -> void:
	var checked: int = 0
	for card in _cards_in(CARDS_DIR):
		if card.tempered == null:
			continue
		checked += 1
		var original: CardView = await _view(card)
		var tempered: CardView = await _view(card.tempered)
		var original_material: ShaderMaterial = original.get_name_finish()
		var tempered_material: ShaderMaterial = tempered.get_name_finish()
		_expect_eq(tempered_material != null, original_material != null, "%s wears a finish exactly when %s does" % [card.tempered.card_name, card.card_name])
		if original_material != null and tempered_material != null:
			_expect((tempered_material.get_shader_parameter("base_color") as Color).is_equal_approx(original_material.get_shader_parameter("base_color")), "...the same base")
		original.queue_free()
		tempered.queue_free()
	_expect(checked > 0, "Tempered cards to check (%d)" % checked)
	_completed += 1

# --- Helpers ---

# A real card of `rarity` from the card data - or, for Ultra Rare, which
# no card is yet, a Rare's copy retagged.
func _card_of(rarity: CardData.CardRarity) -> CardData:
	for card in _cards_in(CARDS_DIR):
		if card.rarity == rarity:
			return card
	if rarity == CardData.CardRarity.ULTRA_RARE:
		var rare: CardData = _card_of(CardData.CardRarity.RARE)
		if rare != null:
			var ultra := rare.duplicate() as CardData
			ultra.rarity = CardData.CardRarity.ULTRA_RARE
			return ultra
	return null

func _cards_in(dir: String) -> Array[CardData]:
	var cards: Array[CardData] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres"):
			var card := load(dir.path_join(file)) as CardData
			if card != null:
				cards.append(card)
	return cards

func _view(card: CardData) -> CardView:
	var view := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	root.add_child(view)
	await process_frame
	if card != null:
		view.set_card_data(card)
	return view

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: " + message)
