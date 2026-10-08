extends SceneTree

# Headless probe for the rules keywords - one table (KeywordTable, ui/
# keywords.tres) that both bolds a word on a card face and defines it on
# hover - and the definition's hover on CardView: where a keyword is on
# the face, when a definition may show, and where it sits.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/keyword_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# The hover is driven through CardView's own seams (keyword_at(),
# keyword_hover_allowed(), and _show_keyword() for a word the hit test
# found) rather than a real cursor, which headless has none of. The fight
# case loads the real region scene and arms a card through
# BattleController.request_play(), as collateral_probe does; the
# inspect cases open the real DeckView and compendium. Untyped against
# anything that names the RunState autoload.

const CASES := 10
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const DECK_PANEL_PATH := "res://ui/deck_panel.gd"
const COMPENDIUM_SCENE_PATH := "res://ui/card_compendium.tscn"
const NO_FURTHER_PATH := "res://cards/data/no_further.tres"
const CORNERED_PATH := "res://cards/data/cornered.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const KEYWORDS: Array[String] = ["Toll", "Grace", "Critical", "Drain", "Spent", "Consumed"]
const DEFINITIONS: Dictionary = {
	"Toll": "Gained when you lose HP to your own cards. Carries between fights; up to 5 carries to the next floor.",
	"Grace": "After enemy hits get through your Block, damage you deal on your next turn wins HP back, up to half the largest hit.",
	"Critical": "At or below 30% of your max HP.",
	"Drain": "Heal for the HP the damage takes from enemies, up to the Drain's number if it has one.",
	"Spent": "Removed for the rest of this fight once played.",
	"Consumed": "Removed from your deck after the fight in which it is played.",
}
const SCALES: Array[float] = [0.95, 1.15, 2.2]
const ENEMY_HP := 999
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_table()
	_check_live_values()
	await _check_hit_test()
	await _check_hit_test_scales()
	await _check_strike_label()
	await _check_full_ink_when_faded()
	await _check_hand_gating()
	await _check_hand_above()
	await _check_deck_view_below()
	await _check_compendium_below()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("keyword_probe: PASSED")
		quit(0)
	else:
		print("keyword_probe: %d FAILED" % _failures)
		quit(1)

# --- Table ---

# The bold list is the table's words, in its order; every word defines
# itself, its tokens filled; a word that isn't one defines nothing.
func _check_table() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var table: KeywordTable = KeywordTable.shared()
	_expect_eq(table.keywords(), KEYWORDS, "The table's keywords")
	_expect_eq(CardView.KEYWORDS, KEYWORDS, "...are exactly the words a card face bolds")
	for word: String in KEYWORDS:
		_expect_eq(table.definition(word), DEFINITIONS[word], "%s's definition" % word)
		_expect(not table.definition(word).contains("{"), "...with every token filled")
	_expect_eq(table.definition("Block"), "", "A word that isn't a keyword defines nothing")
	_expect(CardView._format_rules("Spent.").contains("[b]Spent[/b]"), "Spent is set in bold")
	# A keyword's plural is the keyword: bold as written, its definition
	# the singular's. Only a plural - a longer word isn't one.
	_expect_eq(CardView._format_rules("It Drains twice."), "It [b]Drains[/b] twice.", "Drains is set in bold, as written")
	_expect_eq(table.definition("Drains"), DEFINITIONS["Drain"], "...and reads Drain's definition")
	_expect_eq(CardView._format_rules("Draining."), "Draining.", "Draining isn't a keyword")
	_expect_eq(CardView._format_rules("Your Attacks deal 3 more."), "Your Attacks deal 3 more.", "Attack is plain text, not a keyword")
	_completed += 1

# Critical's threshold and Toll's carry read the run's character as it
# stands, and the Wanderer's data with no run.
func _check_live_values() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var character: CharacterData = (load(CHARACTER_PATH) as CharacterData).duplicate()
	character.critical_hp_fraction = 0.25
	character.toll_carry_cap = 3
	_run_state.set("character", character)
	var table: KeywordTable = KeywordTable.shared()
	_expect_eq(table.definition("Critical"), "At or below 25% of your max HP.", "Critical reads the live fraction: 25%")
	_expect_eq(table.definition("Toll"), "Gained when you lose HP to your own cards. Carries between fights; up to 3 carries to the next floor.", "Toll reads the live carry cap: 3")
	_run_state.set("character", null)
	_expect_eq(table.definition("Critical"), DEFINITIONS["Critical"], "With no run, the Wanderer's 30%")
	_run_state.call("new_run", load(CHARACTER_PATH))
	_completed += 1

# --- Hit test ---

# Each bold keyword on a face is found at its own rect's centre, inside
# the rules text; a point off every keyword finds none.
func _check_hit_test() -> void:
	var view: CardView = await _card_view(NO_FURTHER_PATH)
	var rects: Array[Dictionary] = view.keyword_rects()
	var words: Array[String] = []
	for entry: Dictionary in rects:
		words.append(String(entry["keyword"]))
	_expect_eq(words, ["Critical", "Spent"] as Array[String], "No Further's keywords, in text order")
	var rules: Rect2 = view.rules_text.get_rect().grow(4.0)
	for entry: Dictionary in rects:
		var rect: Rect2 = entry["rect"]
		_expect(rules.encloses(rect), "%s's rect %s sits in the rules text %s" % [entry["keyword"], rect, rules])
		_expect_eq(view.keyword_at(rect.get_center()), entry["keyword"], "...and is found at its centre")
	var spent: Rect2 = _rect_of(rects, "Spent")
	var critical: Rect2 = _rect_of(rects, "Critical")
	_expect(critical.position.y < spent.position.y, "Critical's line sits above Spent's")
	_expect_eq(view.keyword_at(Vector2(view.size.x / 2.0, 20.0)), "", "The name line finds no keyword")
	_expect_eq(view.keyword_at(Vector2(critical.position.x - 6.0, critical.get_center().y)), "", "Beside Critical, nothing")
	var cornered: CardView = await _card_view(CORNERED_PATH)
	var found: Array[String] = []
	for entry: Dictionary in cornered.keyword_rects():
		found.append(String(entry["keyword"]))
	_expect_eq(found, ["Critical"] as Array[String], "Cornered's one keyword")
	# A plural on the face: no card prints one today, so a probe-only card
	# reads "Drains" - found as Drain, its rect over the whole word as
	# written.
	var drains_card := CardData.new()
	drains_card.card_name = "Probe Drains"
	drains_card.description = "Your next hit Drains."
	var plural_view: CardView = await _card_view_of(drains_card)
	var plural: Array[Dictionary] = plural_view.keyword_rects()
	_expect_eq(plural.size(), 1, "The probe card has one keyword")
	if not plural.is_empty():
		var drains: Rect2 = plural[0]["rect"]
		_expect_eq(String(plural[0]["keyword"]), "Drain", "...its \"Drains\" resolving to Drain")
		_expect_eq(plural_view.keyword_at(drains.get_center()), "Drain", "...found at its centre")
		var bold: Font = plural_view.rules_text.get_theme_font("bold_font")
		var font_size: int = plural_view.rules_text.get_theme_font_size("normal_font_size")
		_expect(drains.size.x >= bold.get_string_size("Drains", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, "...its rect as wide as \"Drains\" (%.1f)" % drains.size.x)
	_free_views()
	_completed += 1

# The hit test is in the card's own pixels, so a point on screen finds the
# same word at the hand's, hover's and inspect's scales.
func _check_hit_test_scales() -> void:
	var view: CardView = await _card_view(NO_FURTHER_PATH)
	var centre: Vector2 = Vector2()
	for entry: Dictionary in view.keyword_rects():
		if String(entry["keyword"]) == "Spent":
			centre = (entry["rect"] as Rect2).get_center()
	for card_scale: float in SCALES:
		view.scale = Vector2.ONE * card_scale
		view.position = Vector2(300.0, 100.0)
		await process_frame
		var on_screen: Vector2 = view.get_global_transform() * centre
		var back: Vector2 = view.get_global_transform().affine_inverse() * on_screen
		_expect_eq(view.keyword_at(back), "Spent", "At %.2f, the point on screen over Spent finds it" % card_scale)
	_free_views()
	_completed += 1

# The STRIKE type label answers like a keyword - only the word, not the
# label's whole width - and shows "An Attack card." through the same
# reveal; a card of another type has nothing there, and the word is no
# KeywordTable entry (so it is never bolded in rules text).
func _check_strike_label() -> void:
	var slash: CardView = await _card_view(SLASH_PATH)
	var label: Rect2 = slash.strike_label_rect()
	_expect(label.has_area(), "Slash has a STRIKE label rect (%s)" % label)
	_expect(slash.type_label.get_rect().grow(4.0).encloses(label), "...inside its type label %s" % slash.type_label.get_rect())
	_expect(label.size.x < slash.type_label.size.x * 0.6, "...only as wide as the word (%.1f of %.1f)" % [label.size.x, slash.type_label.size.x])
	_expect_eq(slash.keyword_at(label.get_center()), CardView.STRIKE_LABEL_WORD, "...and the word answers STRIKE")
	_expect_eq(slash.keyword_at(Vector2(label.position.x - 8.0, label.get_center().y)), "", "Beside the word, nothing")
	slash.call("_show_keyword", CardView.STRIKE_LABEL_WORD)
	var reveal: Node = slash.get_node("KeywordReveal")
	_expect_eq(Array(reveal.get("_lines")), ["An Attack card."], "The reveal reads \"An Attack card.\"")
	_expect_eq(Array(reveal.get("_names")), [CardView.STRIKE_LABEL_WORD], "...led by STRIKE")
	_expect(not KeywordTable.shared().keywords().has(CardView.STRIKE_LABEL_WORD) and not KeywordTable.shared().keywords().has("Strike"), "STRIKE is not a KeywordTable word")
	var brace: CardView = await _card_view(BRACE_PATH)
	_expect(not brace.strike_label_rect().has_area(), "Brace (GUARD) has no STRIKE rect")
	_expect_eq(brace.keyword_at(brace.type_label.get_rect().get_center()), "", "...and its type label answers nothing")
	_free_views()
	_completed += 1

# An unplayable card fades - the definition doesn't: the card's alpha
# and the definition's own multiply back to full ink.
func _check_full_ink_when_faded() -> void:
	var view: CardView = await _card_view(NO_FURTHER_PATH)
	var reveal: Control = view.get_node("KeywordReveal")
	view.set_playable(false)
	_expect(is_equal_approx(view.modulate.a, view.unplayable_alpha), "An unplayable card keeps its fade")
	_expect(is_equal_approx(view.modulate.a * reveal.modulate.a, 1.0), "...and its definition reads at full ink (%.3f)" % (view.modulate.a * reveal.modulate.a))
	view.set_playable(true)
	_expect(is_equal_approx(reveal.modulate.a, 1.0), "Playable again: the definition at its own 1")
	_free_views()
	var faded: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	faded.modulate.a = faded.unplayable_alpha
	root.add_child(faded)
	_views.append(faded)
	await process_frame
	var late: Control = faded.get_node("KeywordReveal")
	_expect(is_equal_approx(faded.modulate.a * late.modulate.a, 1.0), "A fade set before _ready() is taken out too")
	_free_views()
	_completed += 1

# --- Hand ---

# A lifted hand card may show a definition; arming it takes the
# definition away and allows none, and the other cards, suppressed while
# it's armed, allow none either.
func _check_hand_gating() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var spent_card: CardData = await _deal(controller, NO_FURTHER_PATH)
		var slash_view: CardView = _view(controller, slash)
		var other_view: CardView = _view(controller, spent_card)
		_expect(not slash_view.keyword_hover_allowed(), "A resting hand card shows no definition")
		other_view.set_hovered(true)
		await _frames(20)
		_expect(other_view.keyword_hover_allowed(), "Lifted, it may")
		other_view.call("_show_keyword", "Spent")
		_expect_eq(other_view.get_hovered_keyword(), "Spent", "...and shows Spent")
		other_view.set_hovered(false)
		_expect_eq(other_view.get_hovered_keyword(), "", "Leaving the card takes it away")
		slash_view.set_hovered(true)
		await _frames(20)
		slash_view.call("_show_keyword", "Spent")
		controller.call("request_play", slash_view)
		await _frames(20)
		_expect(bool(controller.call("is_awaiting_target")), "Slash is armed, awaiting a target")
		_expect(not slash_view.keyword_hover_allowed(), "Armed, it allows no definition")
		_expect_eq(slash_view.get_hovered_keyword(), "", "...and the one up is gone")
		other_view.set_hovered(true)
		await _frames(5)
		_expect(not other_view.keyword_hover_allowed(), "While it's armed, another card allows none either")
		controller.call("cancel_target")
		await _frames(60)
		other_view.set_hovered(false)
		other_view.set_hovered(true)
		await _frames(20)
		_expect(other_view.keyword_hover_allowed(), "Disarmed, the other card may again")
	await _teardown()
	_completed += 1

# In the hand the definition sits above the card, keyword_reveal_gap_px
# off its top edge.
func _check_hand_above() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var card: CardData = await _deal(controller, NO_FURTHER_PATH)
		var view: CardView = _view(controller, card)
		view.set_hovered(true)
		await _frames(30)
		view.call("_show_keyword", "Spent")
		await _frames(3)
		_expect(not view.keyword_reveal_below(), "A hand card's definition goes above")
		var reveal: Rect2 = _reveal_rect(view)
		var card_rect: Rect2 = _screen_rect(view)
		_expect(reveal.size.y > 0.0, "...and has its lines")
		_expect(absf(card_rect.position.y - view.keyword_reveal_gap_px - reveal.end.y) <= 1.0, "...ending the gap above the card's top (reveal %s, card %s)" % [reveal, card_rect])
		_expect(not reveal.intersects(card_rect), "...clear of the card")
		_expect(absf(reveal.get_center().x - card_rect.get_center().x) <= 1.0, "...centred on it")
	await _teardown()
	_completed += 1

# --- Inspect ---

# DeckView: the inspected card defines its keywords, below it, in the
# view's light ink - and once it's back in the grid, no longer.
func _check_deck_view_below() -> void:
	var cards: Array[CardData] = [load(SLASH_PATH) as CardData, load(CORNERED_PATH) as CardData, load(BRACE_PATH) as CardData]
	var deck_view: Node = load(DECK_PANEL_PATH).open_view(self, cards, "Deck")
	await _frames(20)
	var cornered: CardView = _find_view(deck_view, "Cornered")
	_expect(not cornered.keyword_hover_allowed(), "A grid card shows no definition")
	deck_view.call("_begin_inspect", cornered, cornered.get_parent())
	await _frames(30)
	_expect(cornered.keyword_hover_allowed(), "Inspected, it may")
	_expect(cornered.keyword_reveal_below(), "...below the card")
	_expect_eq(cornered.keyword_reveal_ink, deck_view.get("inspect_keyword_ink"), "...in the deck view's light ink")
	await _expect_below(cornered, "Deck view")
	deck_view.call("_end_inspect")
	await _frames(30)
	_expect(not cornered.keyword_hover_allowed(), "Back in the grid, none")
	_expect_eq(cornered.get_hovered_keyword(), "", "...and the definition is gone")
	deck_view.call("close")
	await _frames(10)
	_completed += 1

# The compendium: the same, in its own (dark) ink on its pale page.
func _check_compendium_below() -> void:
	var compendium: Node = (load(COMPENDIUM_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(compendium)
	await _frames(30)
	var cornered: CardView = _find_view(compendium, "Cornered")
	if cornered == null:
		_fail("Cornered is not in the compendium")
	else:
		compendium.call("_begin_inspect", cornered, cornered.get_parent())
		await _frames(30)
		_expect(cornered.keyword_hover_allowed(), "Compendium: inspected, it may")
		_expect(cornered.keyword_reveal_below(), "...below the card")
		_expect_eq(cornered.keyword_reveal_ink, Color(0.165, 0.165, 0.18), "...in the card's own ink")
		await _expect_below(cornered, "Compendium")
	compendium.queue_free()
	await _frames(5)
	_completed += 1

# --- Helpers ---

# Shows Critical on `view` and checks it sits the gap below the card,
# centred, clear of it and on screen.
func _expect_below(view: CardView, where: String) -> void:
	view.call("_show_keyword", "Critical")
	await _frames(3)
	var reveal: Rect2 = _reveal_rect(view)
	var card_rect: Rect2 = _screen_rect(view)
	_expect(reveal.size.y > 0.0, "%s: the definition has its lines" % where)
	_expect(absf(reveal.position.y - (card_rect.end.y + view.keyword_reveal_gap_px)) <= 1.0, "%s: it starts the gap below the card's bottom (reveal %s, card %s)" % [where, reveal, card_rect])
	_expect(not reveal.intersects(card_rect), "%s: clear of the card" % where)
	_expect(absf(reveal.get_center().x - card_rect.get_center().x) <= 1.0, "%s: centred on it" % where)
	_expect(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(reveal), "%s: on screen" % where)

func _reveal_rect(view: CardView) -> Rect2:
	var reveal: Control = view.get_node("KeywordReveal")
	return Rect2(reveal.global_position, reveal.size)

func _screen_rect(view: CardView) -> Rect2:
	var xf: Transform2D = view.get_global_transform()
	var rect := Rect2(xf * Vector2.ZERO, Vector2.ZERO)
	for corner: Vector2 in [Vector2(view.size.x, 0.0), view.size, Vector2(0.0, view.size.y)]:
		rect = rect.expand(xf * corner)
	return rect

func _find_view(host: Node, card_name: String) -> CardView:
	for node in host.find_children("*", "CardView", true, false):
		var view := node as CardView
		if view.card_data != null and view.card_data.card_name == card_name:
			return view
	return null

var _views: Array[CardView] = []

# The rect of the first `keyword` in a face's keyword_rects().
func _rect_of(rects: Array[Dictionary], keyword: String) -> Rect2:
	for entry: Dictionary in rects:
		if String(entry["keyword"]) == keyword:
			return entry["rect"]
	return Rect2()

func _card_view(path: String) -> CardView:
	return await _card_view_of(load(path) as CardData)

func _card_view_of(data: CardData) -> CardView:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	root.add_child(view)
	# _ready() first: before the tree's first frame it hasn't run yet.
	await process_frame
	view.set_card_data(data)
	_views.append(view)
	await _frames(3)
	return view

func _free_views() -> void:
	for view in _views:
		view.queue_free()
	_views.clear()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

# A fresh run and a fresh fight on floor 1 against its first enemy, made
# unkillable here, with an empty hand and 3 Energy.
func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		target = node as Node3D
		break
	if target == null:
		_fail("no enemy on floor 1")
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	controller.get("deck").call("discard_hand")
	(controller.get("player") as Combatant).energy = 3
	await process_frame
	return controller

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	await _frames(5)

func _deal(controller: Node, path: String) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
	var deck: Object = controller.get("deck")
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await _frames(10)
	# Drawn cards fly in from the DECK readout one at a time, the opening
	# hand's ahead of this one: measure it only once every card has landed.
	var hand: Object = controller.get("_hand_container")
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		if (hand.get("_waiting_slots") as Dictionary).is_empty() and (hand.get("_arrival_tweens") as Dictionary).is_empty():
			break
		await process_frame
	return card

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
