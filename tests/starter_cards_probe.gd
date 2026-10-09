extends SceneTree

# Headless probe for the Wanderer's starting deck and its starter cards -
# Slash, Bite Down, and Brace as an enemy-targeted debuff - plus played
# stance and power cards leaving the fight's rotation. Rules layer and
# the real .tres data; no field scene:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/starter_cards_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# BattleController is reached through load()/call() only - it names
# RunState, and a script typed against it here would compile before the
# autoloads register (see kill_order_probe.gd's own note).

const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BATTLE_CONTROLLER_PATH := "res://battle/battle_controller.gd"
const CASES := 15
# Cards whose one status prints as two lines - a rule written as two
# sentences (Sentence's countdown and its hurry; The Return's count and
# its Drain). Every other status-applying effect is one line.
const TWO_LINE_STATUS_CARDS: Array[String] = ["Sentence", "The Return"]
# The rules text size each card lands at outside a fight; any card not
# listed fits at the first size, 15, cleanly - inside the rules margins
# (CardView.rules_margin_px) and no lone last word. A card that moves
# here has changed its wording - or needs to.
const SHRUNK_RULES: Dictionary = {
	"Bide": 14,
	"Collateral": 13,
	"Deny": 13,
	"Cornered": 14,
	"Last Resort": 14,
	"Last Wager": 13,
	"No Further": 12,
	"Refuse the End": 13,
	"The Return": 13,
}
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
# The numeral's ink stays this far below the card's top edge - the room it
# had beside the inset rule, kept now the rule is gone.
const NUMERAL_TOP_CLEAR_PX := 5.0
const CARD_DIRS: Array[String] = ["res://cards/data/", "res://cards/neutral/"]
# The tempered versions (CardData.tempered) - in no class's folder, so only
# the rules-text pattern reads them here; temper_probe checks the rest.
const TEMPERED_DIR := "res://cards/tempered/"
# The cards with art, by file - the starters, Carve, Cornered, Hold Fast,
# Come Due, No Further, Sentence, Last Wager, The Return, Blood Arc,
# Collateral, Ransom, Leverage, Self-Eater, Unbroken, Small Price, Bide,
# Deny, Refuse the End, With Regards, Debt Forgiven, Last Resort, Dying
# Light, Blood Advance, Second Swing, Garnish, Claw Back, Gnaw and
# Settled Account.
# Every other card has none yet.
const CARD_ART: Dictionary = {
	"slash": "res://cards/art/Wanderer/Slash.png",
	"bite_down": "res://cards/art/Wanderer/Bite Down.png",
	"brace": "res://cards/art/Wanderer/Brace.png",
	"reckoning": "res://cards/art/Wanderer/Reckoning.png",
	"down_payment": "res://cards/art/Wanderer/Down Payment.png",
	"carve": "res://cards/art/Wanderer/Carve.png",
	"cornered": "res://cards/art/Wanderer/Cornered.png",
	"hold_fast": "res://cards/art/Wanderer/Hold Fast.png",
	"come_due": "res://cards/art/Wanderer/Come Due.png",
	"no_further": "res://cards/art/Wanderer/No Further.png",
	"sentence": "res://cards/art/Wanderer/Sentence.png",
	"last_wager": "res://cards/art/Wanderer/Last Wager.png",
	"the_return": "res://cards/art/Wanderer/The Return.png",
	"blood_arc": "res://cards/art/Wanderer/Blood Arc.png",
	"collateral": "res://cards/art/Wanderer/Collateral.png",
	"ransom": "res://cards/art/Wanderer/Ransom.png",
	"leverage": "res://cards/art/Wanderer/Leverage.png",
	"self_eater": "res://cards/art/Wanderer/Self-Eater.png",
	"unbroken": "res://cards/art/Wanderer/Unbroken.png",
	"small_price": "res://cards/art/Wanderer/Small Price.png",
	"bide": "res://cards/art/Wanderer/Bide.png",
	"deny": "res://cards/art/Wanderer/Deny.png",
	"refuse_the_end": "res://cards/art/Wanderer/Refuse the End.png",
	"with_regards": "res://cards/art/Wanderer/With Regards.png",
	"debt_forgiven": "res://cards/art/Wanderer/Debt Forgiven.png",
	"last_resort": "res://cards/art/Wanderer/Last Resort.png",
	"dying_light": "res://cards/art/Wanderer/Dying Light.png",
	"blood_advance": "res://cards/art/Wanderer/Blood Advance.png",
	"second_swing": "res://cards/art/Wanderer/Second Swing.png",
	"garnish": "res://cards/art/Wanderer/Garnish.png",
	"claw_back": "res://cards/art/Wanderer/Claw Back.png",
	"gnaw": "res://cards/art/Wanderer/Gnaw.png",
	"settled_account": "res://cards/art/Wanderer/Settled Account.png",
}

var _failures: int = 0
# Cases that ran to their end. A script error aborts a case without
# failing anything, so the total is checked too.
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	_check_starting_deck()
	_check_slash_and_bite_down()
	_check_brace_single_hit()
	_check_brace_multi_hit()
	_check_brace_waits_through_defend()
	_check_brace_spent_when_blocked()
	_check_brace_survives_interrupt()
	_check_brace_reapplied()
	_check_brace_face()
	_check_lasting_cards_leave_rotation()
	await _check_starter_art()
	await _check_face_layout()
	await _check_rules_text_pattern()
	await _check_toll_cards()
	await _check_blood_arc_effect()
	if _completed != CASES:
		_failures += 1
		print("FAIL: only %d of %d cases ran to the end" % [_completed, CASES])
	if _failures == 0:
		print("starter_cards_probe: PASSED")
		quit(0)
	else:
		print("starter_cards_probe: %d FAILED" % _failures)
		quit(1)

# --- Cases ---

func _check_starting_deck() -> void:
	var character: CharacterData = load(CHARACTER_PATH) as CharacterData
	var counts: Dictionary = {}
	var total: int = 0
	for card: CardData in character.starting_deck_counts:
		var count: int = character.starting_deck_counts[card]
		counts[card.card_name] = count
		total += count
	_expect_eq(total, 10, "Starting deck is 10 cards")
	_expect_eq(counts, {"Slash": 4, "Bite Down": 2, "Brace": 2, "Reckoning": 1, "Down Payment": 1}, "Starting deck contents")
	_completed += 1

func _check_slash_and_bite_down() -> void:
	var player: Combatant = _player(50)
	_expect_eq(_deal(_card("slash"), player), 6, "Slash deals 6")
	_expect_eq(_deal(_card("bite_down"), player), 8, "Bite Down deals 8")
	_expect_eq(player.hp, 48, "Bite Down loses 2 HP")
	_expect_eq(player.toll, 2, "Bite Down makes 2 Toll")
	player = _player(2)
	_deal(_card("bite_down"), player)
	_expect_eq(player.hp, 0, "Bite Down can still kill")
	_completed += 1

func _check_brace_single_hit() -> void:
	var player: Combatant = _player(50)
	var data: EnemyData = _enemy_data([_attack(7, 1)])
	var enemy: Combatant = _enemy(data)
	var other_data: EnemyData = _enemy_data([_attack(7, 1)])
	var other: Combatant = _enemy(other_data)
	_brace(player, enemy)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(int(preview["per_hit"]), 3, "Braced intent previews 7 -> 3")
	_expect_eq(int(EnemyTurn.preview_intent(other, other_data, player)["per_hit"]), 7, "Other enemy's intent untouched")
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(result["damage_to_hp"]), 3, "Braced attack lands for 3")
	_expect(not _is_braced(enemy), "Braced gone after the attack")
	EnemyTurn.take_turn(other, other_data, player)
	_expect_eq(player.hp, 50 - 3 - 7, "Other enemy hits in full")
	_completed += 1

func _check_brace_multi_hit() -> void:
	var player: Combatant = _player(50)
	var data: EnemyData = _enemy_data([_attack(3, 3)])
	var enemy: Combatant = _enemy(data)
	_brace(player, enemy)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(int(preview["per_hit"]), 1, "Braced 3x3 previews 1 per hit")
	_expect_eq(int(preview["damage_to_hp"]), 3, "Braced 3x3 previews 3 total")
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(result["damage_to_hp"]), 3, "Every hit of 3x3 halved: 3 total")
	_expect(not _is_braced(enemy), "Braced gone after the whole attack")
	_completed += 1

func _check_brace_waits_through_defend() -> void:
	var player: Combatant = _player(50)
	var data: EnemyData = _enemy_data([_defend(5), _attack(8, 1)])
	var enemy: Combatant = _enemy(data)
	_brace(player, enemy)
	EnemyTurn.take_turn(enemy, data, player)
	_expect(_is_braced(enemy), "Braced stays through a Defend")
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(result["damage_to_hp"]), 4, "Next attack after the Defend is halved")
	_expect(not _is_braced(enemy), "Then Braced is gone")
	_completed += 1

func _check_brace_spent_when_blocked() -> void:
	var player: Combatant = _player(50)
	player.block = 10
	var data: EnemyData = _enemy_data([_attack(8, 1), _attack(8, 1)])
	var enemy: Combatant = _enemy(data)
	_brace(player, enemy)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(result["damage_to_hp"]), 0, "Fully blocked")
	_expect_eq(player.block, 6, "Block took the halved 4")
	_expect(not _is_braced(enemy), "Braced spent even when blocked")
	_completed += 1

func _check_brace_survives_interrupt() -> void:
	var player: Combatant = _player(50)
	var charge: EnemyIntent = _attack(10, 1)
	charge.interrupt_threshold = 5
	var data: EnemyData = _enemy_data([charge, _attack(10, 1)])
	var enemy: Combatant = _enemy(data)
	_brace(player, enemy)
	enemy.damage_taken_this_turn = 5
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["interrupted"]), "Attack interrupted")
	_expect(_is_braced(enemy), "Braced stays through an interrupted attack")
	_completed += 1

func _check_brace_reapplied() -> void:
	var player: Combatant = _player(50)
	var data: EnemyData = _enemy_data([_attack(8, 1)])
	var enemy: Combatant = _enemy(data)
	_brace(player, enemy)
	_brace(player, enemy)
	var braced: int = 0
	for active in enemy.statuses:
		if active.data.id == "braced":
			braced += 1
			_expect_eq(active.magnitude, -50, "Reapplied Brace stays at 50%")
	_expect_eq(braced, 1, "One Braced, not two")
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(result["damage_to_hp"]), 4, "Twice-Braced 8 -> 4, not 2")
	_completed += 1

func _check_brace_face() -> void:
	var card: CardData = _card("brace")
	_expect_eq(card.target_type, CardData.TargetType.ENEMY, "Brace targets an enemy")
	_expect_eq(card.battle_animation, &"Brace", "Brace plays the Brace clip")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.GUARD, "Brace reads GUARD")
	var player: Combatant = _player(50)
	_brace(player, _enemy(_enemy_data([_attack(8, 1)])))
	_expect(player.statuses.is_empty(), "Nothing lands on the Wanderer")
	_completed += 1

# Each starter card carries its own art, mipmapped; nothing else has any.
# A face with art shows it and hides the glyph; one without keeps the
# glyph and shows no image.
func _check_starter_art() -> void:
	for dir in CARD_DIRS:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres"):
				continue
			var card := load(dir + file) as CardData
			var key: String = file.get_basename()
			if dir == "res://cards/data/" and CARD_ART.has(key):
				_expect(card.art != null and card.art.resource_path == CARD_ART[key], "%s shows %s (got %s)" % [key, CARD_ART[key], card.art.resource_path if card.art != null else "none"])
				if card.art != null:
					_expect(card.art.get_image().has_mipmaps(), "%s's art is mipmapped" % key)
			else:
				_expect(card.art == null, "%s has no art yet" % key)

	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	var with_art: CardView = scene.instantiate()
	var without_art: CardView = scene.instantiate()
	root.add_child(with_art)
	root.add_child(without_art)
	await process_frame
	with_art.set_card_data(_card("slash"))
	without_art.set_card_data(_card("endure"))
	_expect(with_art.art_rect.visible and with_art.art_rect.texture == _card("slash").art, "Slash's face shows its art")
	_expect(not with_art.glyph.visible, "...and hides the glyph")
	_expect_eq(with_art.art_rect.size, with_art.art_field.size, "...filling the art field")
	_expect_eq(with_art.art_rect.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "...as a cover crop")
	_expect(not without_art.art_rect.visible and without_art.art_rect.texture == null, "Endure's face shows no image")
	_expect(without_art.glyph.visible, "...and keeps its glyph")
	# One shared material, tuned in one place; its defaults leave the art
	# as painted.
	var material := with_art.art_rect.material as ShaderMaterial
	_expect(material != null and material == without_art.art_rect.material, "Every face shares the one card-art material")
	if material != null:
		_expect_eq(material.resource_path, "res://battle/card_art_material.tres", "...card_art_material.tres")
		_expect_eq(material.shader.get_shader_uniform_list().size(), 3, "The card-art shader compiles (3 uniforms)")
		_expect_eq(material.get_shader_parameter("art_contrast"), 1.0, "art_contrast defaults to 1.0 (off)")
		_expect_eq(material.get_shader_parameter("art_tint"), Color.WHITE, "art_tint defaults to white (off)")
	with_art.set_card_data(_card("endure"))
	_expect(not with_art.art_rect.visible and with_art.glyph.visible, "A reused face drops the art for a card without")
	with_art.queue_free()
	without_art.queue_free()
	_completed += 1

# The art field is one rect on every card; the rules text steps down to
# fit under it, and no current card grows. Past the smallest size a card
# grows downward instead, and a name too long for one line is clipped to
# one.
func _check_face_layout() -> void:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	var view: CardView = scene.instantiate()
	root.add_child(view)
	await process_frame
	var art_top: float = view.header_height + view.header_field_gap
	var art_rect: Rect2 = Rect2(Vector2(view.outer_margin, art_top), view.art_field_size)
	_expect_eq(art_rect, Rect2(12.0, 48.0, 176.0, 146.0), "The art field is 176 x 146 at (12, 48)")
	for dir in CARD_DIRS:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres"):
				continue
			var card := load(dir + file) as CardData
			view.set_card_data(card)
			_expect_eq(Rect2(view.art_field.position, view.art_field.size), art_rect, "%s's art field" % card.card_name)
			_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), SHRUNK_RULES.get(card.card_name, 15), "%s's rules size" % card.card_name)
			_expect_eq(view.size, view.card_size, "%s keeps the card's size" % card.card_name)
			_expect(view.rules_text.position.y + view.rules_text.size.y <= _type_baseline(view) + _ink_top(view.type_label, view.type_label_font_size_px), "%s's text ends above the type label" % card.card_name)
			_check_rules_block(view, card.card_name)
			# ATTACK <=> STRIKE, both ways: the label is how a reader knows
			# which cards the "your Attacks" effects touch (DESIGN.md).
			var is_attack: bool = card.card_type == CardData.CardType.ATTACK
			_expect(is_attack == (view.type_label.text == "STRIKE"), "%s is %s and labelled %s - every ATTACK reads STRIKE and every STRIKE is an ATTACK" % [card.card_name, CardData.CardType.keys()[card.card_type], view.type_label.text])
			# The header holds the ledger rule and the "-N HP" line without
			# adding a row - the HP ink clear of the art field by 4 px - and
			# the numeral's ink keeps NUMERAL_TOP_CLEAR_PX off the top edge.
			if view.hp_cost_label.visible:
				_expect(view.hp_cost_label.position.y + view.hp_cost_label.get_theme_font("font").get_ascent(view.hp_cost_font_size_px) <= art_top - 4.0, "%s's HP line sits clear of the art" % card.card_name)
				_expect(view.cost_rule.visible and view.cost_rule.position.y < view.hp_cost_baseline_px + _ink_top(view.hp_cost_label, view.hp_cost_font_size_px), "%s's ledger rule sits over its HP line" % card.card_name)
			_expect(view.header_baseline_px + _ink_top(view.cost_label, view.cost_font_size_px) >= NUMERAL_TOP_CLEAR_PX, "%s's numeral sits %.0f px clear of the top edge" % [card.card_name, NUMERAL_TOP_CLEAR_PX])

	var footer_y: float = _type_baseline(view)
	# The footer by ink: the type label's baseline 9 px off the bottom
	# edge.
	_expect_eq(footer_y, 271.0, "The type label's baseline sits at y 271")
	var long_card := CardData.new()
	long_card.card_name = "Probe Long"
	long_card.description = "Lose 2 HP. Draw 1. Gain 5 Toll. Deal 6 damage to all enemies. Gain 8 block. Heal 3 HP. If this kills, gain 1 energy. Exhaust a card in your hand. Discard 2 cards, then draw 2. Next turn, gain 1 energy."
	view.set_card_data(long_card)
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), view.rules_font_sizes[view.rules_font_sizes.size() - 1], "Overlong text sits at the floor size")
	_expect(view.size.y > view.card_size.y, "...and the card grows (%s)" % str(view.size))
	_expect_eq(_type_baseline(view) - (view.size.y - view.card_size.y), footer_y, "...its footer moving down with it")
	_expect_eq(Rect2(view.art_field.position, view.art_field.size), art_rect, "...its art field unmoved")
	_check_rules_block(view, long_card.card_name)

	var long_name := CardData.new()
	long_name.card_name = "A Name Far Too Long To Sit Beside Its Cost"
	long_name.description = "Draw 1."
	view.set_card_data(long_name)
	_expect(view.name_label.autowrap_mode == TextServer.AUTOWRAP_OFF and view.name_label.clip_text, "A long name is clipped to one line")
	_expect(view.name_label.position.y + view.name_label.size.y <= art_top, "...clear of the art field")
	_expect_eq(view.size, view.card_size, "A short card back at card_size after a grown one")
	view.queue_free()
	_completed += 1

# The rules block as the label lays it out - its content height, less
# the separations it counts after the last line - is the height the
# fitter modelled (CardView.rules_block_height()), and it sits at true
# centre of the rules area: equal margins above and below, each at least
# rules_margin_px.
func _check_rules_block(view: CardView, card_name: String) -> void:
	var label: RichTextLabel = view.rules_text
	var font_size: int = label.get_theme_font_size("normal_font_size")
	var metrics: Vector3i = view.rules_metrics(font_size)
	var laid_out: float = float(label.get_content_height() - metrics.y - metrics.z)
	var model: float = view.rules_block_height(font_size, label.get_line_count(), _paragraphs(view))
	_expect_eq(laid_out, model, "%s's rules block lays out at the height the fitter modelled" % card_name)
	var area: Vector2 = view.rules_area()
	var above: float = label.position.y - area.x
	var below: float = area.y + (view.size.y - view.card_size.y) - (label.position.y + laid_out)
	_expect(is_equal_approx(above, below), "%s's rules margins match (%.1f above, %.1f below)" % [card_name, above, below])
	_expect(above >= view.rules_margin_px, "%s's rules margins are at least %.0f px (%.1f)" % [card_name, view.rules_margin_px, above])

# The description's authored lines, as CardView counts its paragraphs.
func _paragraphs(view: CardView) -> int:
	return view.card_data.description.strip_edges().split("\n").size()

func _type_baseline(view: CardView) -> float:
	return view.type_label.position.y + view.type_label.get_theme_font("font").get_ascent(view.type_label_font_size_px)

# How far above its baseline a label's text inks, from the glyphs
# themselves (negative = up) - the line box's ascent overstates it.
func _ink_top(label: Label, font_size: int) -> float:
	var ts: TextServer = TextServerManager.get_primary_interface()
	var rid: RID = label.get_theme_font("font").get_rids()[0]
	var top: float = 0.0
	for ch in label.text:
		var glyph: int = ts.font_get_glyph_index(rid, font_size, ch.unicode_at(0), 0)
		top = minf(top, ts.font_get_glyph_offset(rid, Vector2i(font_size, 0), glyph).y)
	return top

# A played stance or power card is exhausted, not discarded; so is a
# Spent or Consumed one; an ordinary card is discarded as before - the
# pile BattleController.exhausts_on_play() names, which Deck.settle_play()
# puts the played card in.
func _check_lasting_cards_leave_rotation() -> void:
	var controller_script := load(BATTLE_CONTROLLER_PATH) as GDScript
	for card_name in ["self_eater", "last_resort", "dying_light", "blood_advance", "samphire", "slash"]:
		var card: CardData = _card(card_name)
		var deck := Deck.new([])
		deck.hand.append(card)
		_expect(deck.begin_play(card), "%s's play begins" % card.card_name)
		_expect(not deck.hand.has(card), "...out of the hand")
		var exhausts: bool = controller_script.call("exhausts_on_play", card)
		deck.settle_play(exhausts)
		deck.end_play()
		var leaves: bool = card.card_type == CardData.CardType.STANCE or card.card_type == CardData.CardType.POWER or card.removal_scope != CardData.RemovalScope.NONE
		if leaves:
			_expect(deck.exhaust_pile.has(card) and not deck.discard_pile.has(card), "%s leaves rotation" % card.card_name)
		else:
			_expect(deck.discard_pile.has(card) and not deck.exhaust_pile.has(card), "%s is discarded as before" % card.card_name)
	_completed += 1

# The rules-text pattern every card follows, so a new one can't drift:
#   - HP paid before any other effect is the cost badge's alone - the
#     text never says "Lose X HP" for it;
#   - HP paid after another effect stays in the text where it happens,
#     as "Then lose X HP." with the effect's own number;
#   - any HP the card costs shows in the badge;
#   - one line per resolution step, in order - TOLL_DAMAGE and TOLL_HEAL
#     spend and then act (2), a hit with a Toll repeat (repeat_toll_cost)
#     lands and then repeats (2), SELF_DAMAGE_TOLL's line is its Toll (the
#     HP is the badge's), a conditional upgrade shares its effect's line,
#     and TWO_LINE_STATUS_CARDS' status takes 2 - and the scope last:
#     "Spent." for a SPENT card, "Consumed." for a CONSUMED one.
func _check_rules_text_pattern() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	var lose_regex := RegEx.new()
	lose_regex.compile("\\bLose (\\d+|\\{hp_cost\\}) HP")
	for dir: String in CARD_DIRS + [TEMPERED_DIR]:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres"):
				continue
			var card := load(dir + file) as CardData
			var lines: PackedStringArray = card.description.strip_edges().split("\n")
			var expected: int = 0
			var upfront: bool = true
			var hp_total: int = 0
			var upfront_hp: int = 0
			for effect in card.effects:
				var self_loss: bool = effect.effect_type == CardEffect.EffectType.SELF_DAMAGE or effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL
				if self_loss:
					hp_total += effect.value
				if self_loss and upfront:
					upfront_hp += effect.value
					# Its Toll is still something the card does.
					if effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL:
						expected += 1
					continue
				upfront = false
				if self_loss:
					var at: String = lines[expected] if expected < lines.size() else "(none)"
					_expect_eq(at, "Then lose %d HP." % effect.value, "%s's HP after another effect reads on its own line %d" % [card.card_name, expected + 1])
					expected += 1
					continue
				expected += _lines_for(effect, card)
			if upfront_hp > 0:
				_expect(lose_regex.search(card.description) == null, "%s's upfront HP is the badge's alone, not its text: %s" % [card.card_name, card.description])
			var spent: bool = card.removal_scope == CardData.RemovalScope.SPENT
			var consumed: bool = card.removal_scope == CardData.RemovalScope.CONSUMED
			if spent or consumed:
				expected += 1
				var scope_line: String = "Spent." if spent else "Consumed."
				_expect_eq(lines[lines.size() - 1], scope_line, "%s ends on %s" % [card.card_name, scope_line])
			_expect_eq(Array(lines).count("Spent."), 1 if spent else 0, "%s says Spent. %s" % [card.card_name, "once" if spent else "nowhere"])
			_expect_eq(Array(lines).count("Consumed."), 1 if consumed else 0, "%s says Consumed. %s" % [card.card_name, "once" if consumed else "nowhere"])
			_expect_eq(lines.size(), expected, "%s has a line per step (%s)" % [card.card_name, card.description.replace("\n", " / ")])
			view.set_card_data(card)
			if hp_total > 0:
				_expect(view.hp_cost_label.visible and view.hp_cost_label.text == "−%d HP" % hp_total, "%s's badge shows its %d HP (%s)" % [card.card_name, hp_total, view.hp_cost_label.text])
			else:
				_expect(not view.hp_cost_label.visible, "%s shows no HP badge" % card.card_name)
	view.free()
	_completed += 1

# Debt Forgiven spends up to 20 Toll and heals 1 HP per 2 spent - only
# the even amount it converts, so an odd point stays held; it and
# Reckoning say their rule outside a fight and their live
# number in a battle hand (CardView's {battle}/{outside} blocks).
func _check_toll_cards() -> void:
	var debt: CardData = _card("debt_forgiven")
	# Toll held, spent, healed - only the even amount it converts is
	# spent: 13 spends 12, heals 6 and leaves 1.
	for case: Array in [[30, 20, 10], [20, 20, 10], [13, 12, 6], [7, 6, 3], [1, 0, 0]]:
		var player: Combatant = _player(40)
		player.max_hp = 70
		player.toll = case[0]
		var ctx := EffectContext.new()
		ctx.player = player
		ctx.enemies = [Combatant.new(100)] as Array[Combatant]
		_resolver.resolve_card(debt, ctx)
		_expect_eq(case[0] - player.toll, case[1], "Debt Forgiven on %d Toll spends %d" % [case[0], case[1]])
		_expect_eq(player.hp - 40, case[2], "...and heals %d" % case[2])
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(debt)
	_expect_eq(view.rules_text.get_parsed_text(), "Spend up to 20 Toll.\nHeal 1 HP per 2 Toll spent.", "Debt Forgiven outside a fight says its rule")
	view.set_card_data(_card("reckoning"))
	_expect_eq(view.rules_text.get_parsed_text(), "Spend all Toll.\nDeal that much damage.", "Reckoning outside a fight says its rule")
	view.free()
	var hand_view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hand_view)
	await process_frame
	var battle := EffectContext.new()
	battle.player = _player(40)
	battle.player.toll = 13
	hand_view.set_bonus_context(battle)
	hand_view.set_toll(13)
	hand_view.set_card_data(debt)
	_expect_eq(hand_view.rules_text.get_parsed_text(), "Spend up to 20 Toll.\nHeal 6 HP.", "In a battle hand on 13 Toll it reads its live heal, 6")
	hand_view.set_card_data(_card("reckoning"))
	_expect_eq(hand_view.rules_text.get_parsed_text(), "Spend all Toll.\nDeal 13 damage.", "...and Reckoning its live 13")
	hand_view.free()
	_completed += 1

# The rules lines one effect takes - see _check_rules_text_pattern().
func _lines_for(effect: CardEffect, card: CardData) -> int:
	match effect.effect_type:
		CardEffect.EffectType.TOLL_DAMAGE, CardEffect.EffectType.TOLL_HEAL:
			return 2
		CardEffect.EffectType.APPLY_STATUS, CardEffect.EffectType.APPLY_STATUS_TO_TARGET:
			return 2 if TWO_LINE_STATUS_CARDS.has(card.card_name) else 1
		CardEffect.EffectType.DAMAGE:
			return 2 if effect.repeat_toll_cost > 0 else 1
	return 1

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(70)
	player.hp = hp
	return player

# Blood Arc's play effect: an ink stroke (BrushStrokeEffect) that builds
# over the enemies it hits and reaches them in battle-line order - the
# near one first, both inside its sweep - whatever order they're listed.
func _check_blood_arc_effect() -> void:
	var card: CardData = _card("blood_arc")
	_expect(not card.play_effect_scene_path.is_empty(), "Blood Arc names a play effect")
	var scene := load(card.play_effect_scene_path) as PackedScene
	var effect := scene.instantiate() as BrushStrokeEffect if scene != null else null
	_expect(effect != null, "...a BrushStrokeEffect scene")
	if effect == null:
		_completed += 1
		return
	var wanderer := Node3D.new()
	var near := Node3D.new()
	var far := Node3D.new()
	for node: Node3D in [wanderer, near, far, effect]:
		root.add_child(node)
	near.global_position = Vector3(4.0, 0.0, 0.0)
	far.global_position = Vector3(7.0, 0.0, 0.0)
	await process_frame
	var targets: Array[Node3D] = [far, near]
	effect.setup(wanderer, targets)
	var built: bool = false
	for child in effect.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			built = (child as MeshInstance3D).mesh.get_surface_count() > 0
	_expect(built, "...which builds its ribbon over them")
	var to_near: float = effect.arrival_delay(near)
	var to_far: float = effect.arrival_delay(far)
	_expect(0.0 < to_near and to_near < to_far and to_far < effect.sweep_time, "...and reaches the near enemy first, both within its %.2f s sweep (%.3f, %.3f)" % [effect.sweep_time, to_near, to_far])
	_expect(_card("slash").play_effect_scene_path.is_empty(), "Slash names none - its hits keep their slash marks")
	# Under a ceiling - the lowest intent readout's bottom edge - its top
	# edge stays readout_margin below it.
	var low := scene.instantiate() as BrushStrokeEffect
	root.add_child(low)
	await process_frame
	low.setup(wanderer, targets, 2.0)
	var top: float = -INF
	for child in low.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			top = (child as MeshInstance3D).get_aabb().end.y
	_expect(top <= 2.0 - low.readout_margin + 0.001, "...and stays %.2f m under the intent readouts (top %.3f under a ceiling at 2.0)" % [low.readout_margin, top])
	for node: Node3D in [wanderer, near, far, effect, low]:
		node.free()
	_completed += 1

# A card by file name - the Wanderer's, else a neutral one (Endure).
func _card(card_name: String) -> CardData:
	var path: String = "res://cards/data/%s.tres" % card_name
	if not ResourceLoader.exists(path):
		path = "res://cards/neutral/%s.tres" % card_name
	return load(path) as CardData

func _attack(damage: int, hits: int) -> EnemyIntent:
	var intent := EnemyIntent.new()
	intent.type = EnemyIntent.IntentType.ATTACK
	intent.value = damage
	intent.hits = hits
	return intent

func _defend(block: int) -> EnemyIntent:
	var intent := EnemyIntent.new()
	intent.type = EnemyIntent.IntentType.DEFEND
	intent.value = block
	return intent

func _enemy_data(intents: Array[EnemyIntent]) -> EnemyData:
	var data := EnemyData.new()
	data.max_hp = 50
	data.intents = intents
	return data

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _brace(player: Combatant, enemy: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy]
	_resolver.resolve_card(_card("brace"), ctx)

func _is_braced(enemy: Combatant) -> bool:
	for active in enemy.statuses:
		if active.data.id == "braced":
			return true
	return false

func _deal(card: CardData, player: Combatant) -> int:
	var enemy := Combatant.new(100)
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy]
	_resolver.resolve_card(card, ctx)
	return 100 - enemy.hp

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		print("FAIL: %s (got %s, expected %s)" % [label, str(actual), str(expected)])
