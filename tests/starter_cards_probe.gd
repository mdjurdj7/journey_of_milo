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
const CASES := 12
# The rules text size each card lands at outside a fight; any card not
# listed fits at the first size, 15, cleanly - room to spare and no lone
# last word (CardView.rules_min_air_px). A card that moves here has
# changed its wording - or needs to.
const SHRUNK_RULES: Dictionary = {
	"Come Due": 13,
	"Cornered": 14,
	"Last Resort": 14,
	"Last Wager": 13,
}
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const CARD_DIRS: Array[String] = ["res://cards/data/", "res://cards/neutral/"]
# The cards with art, by file - the starters and Carve. Every other card
# has none yet.
const CARD_ART: Dictionary = {
	"slash": "res://cards/art/Wanderer/Slash.png",
	"bite_down": "res://cards/art/Wanderer/Bite Down.png",
	"brace": "res://cards/art/Wanderer/Brace.png",
	"reckoning": "res://cards/art/Wanderer/Reckoning.png",
	"down_payment": "res://cards/art/Wanderer/Down Payment.png",
	"carve": "res://cards/art/Wanderer/Carve.png",
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
	_expect_eq(_deal(_card("slash"), player), 5, "Slash deals 5")
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
			# The header holds the ledger rule and the "-N HP" line without
			# adding a row - the HP ink clear of the art field by 4 px - and
			# the numeral's ink clears the inset rule.
			if view.hp_cost_label.visible:
				_expect(view.hp_cost_label.position.y + view.hp_cost_label.get_theme_font("font").get_ascent(view.hp_cost_font_size_px) <= art_top - 4.0, "%s's HP line sits clear of the art" % card.card_name)
				_expect(view.cost_rule.visible and view.cost_rule.position.y < view.hp_cost_baseline_px + _ink_top(view.hp_cost_label, view.hp_cost_font_size_px), "%s's ledger rule sits over its HP line" % card.card_name)
			_expect(view.header_baseline_px + _ink_top(view.cost_label, view.cost_font_size_px) >= float(view.inner_keyline_inset_px + view.inner_keyline_width_px), "%s's numeral clears the inset rule" % card.card_name)

	var footer_y: float = _type_baseline(view)
	# The footer by ink: the type label's baseline 9 px off the bottom
	# edge, 4 px clear of the inset rule.
	_expect_eq(footer_y, 271.0, "The type label's baseline sits at y 271")
	var long_card := CardData.new()
	long_card.card_name = "Probe Long"
	long_card.description = "Lose 2 HP. Draw 1. Gain 5 Toll. Deal 6 damage to all enemies. Gain 8 block. Heal 3 HP. If this kills, gain 1 energy. Exhaust a card in your hand."
	view.set_card_data(long_card)
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), view.rules_font_sizes[view.rules_font_sizes.size() - 1], "Overlong text sits at the floor size")
	_expect(view.size.y > view.card_size.y, "...and the card grows (%s)" % str(view.size))
	_expect_eq(_type_baseline(view) - (view.size.y - view.card_size.y), footer_y, "...its footer moving down with it")
	_expect_eq(Rect2(view.art_field.position, view.art_field.size), art_rect, "...its art field unmoved")

	var long_name := CardData.new()
	long_name.card_name = "A Name Far Too Long To Sit Beside Its Cost"
	long_name.description = "Draw 1."
	view.set_card_data(long_name)
	_expect(view.name_label.autowrap_mode == TextServer.AUTOWRAP_OFF and view.name_label.clip_text, "A long name is clipped to one line")
	_expect(view.name_label.position.y + view.name_label.size.y <= art_top, "...clear of the art field")
	_expect_eq(view.size, view.card_size, "A short card back at card_size after a grown one")
	view.queue_free()
	_completed += 1

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

# A played stance or power card is exhausted, not discarded; an ordinary
# card is discarded as before.
func _check_lasting_cards_leave_rotation() -> void:
	var controller: Object = (load(BATTLE_CONTROLLER_PATH) as GDScript).new()
	for card_name in ["self_eater", "last_resort", "dying_light", "slash"]:
		var card: CardData = _card(card_name)
		var deck := Deck.new([])
		deck.hand.append(card)
		controller.set("deck", deck)
		controller.call("_on_play_animation_finished", card)
		var lasting: bool = card.card_type == CardData.CardType.STANCE or card.card_type == CardData.CardType.POWER
		if lasting:
			_expect(deck.exhaust_pile.has(card) and not deck.discard_pile.has(card), "%s leaves rotation" % card.card_name)
		else:
			_expect(deck.discard_pile.has(card) and not deck.exhaust_pile.has(card), "%s is discarded as before" % card.card_name)
	(controller as Node).free()
	_completed += 1

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(70)
	player.hp = hp
	return player

func _card(card_name: String) -> CardData:
	return load("res://cards/data/%s.tres" % card_name) as CardData

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
