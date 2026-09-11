extends Node
class_name BattleController

# --- View-facing input/targeting signals (unchanged from the previous pass) ---
signal card_played(card: CardData, target: FieldEnemy)
signal hand_changed()
signal target_requested(card: CardData)
signal target_cancelled()

# --- Rules-facing signals - the overlay/FloatingNumber react to these only. ---
signal hp_changed(current: int, max_hp: int)
signal toll_changed(new_toll: int)
signal status_changed()
signal enemy_hp_changed(enemy: FieldEnemy, current: int, max_hp: int)
signal damage_dealt(source: Variant, target: Variant, amount: int, kind: String)
# source/target are each either the String "player" or a FieldEnemy node -
# whichever combatant actually dealt/received the hit.
signal battle_won()
signal battle_lost()

# Path -> copy count, same composition as the old project's STARTING_DECK
# (reference/old_project's run_state.gd) re-pointed at the trimmed
# CardData resources under cards/data/.
const STARTER_DECK_COUNTS: Dictionary = {
	"res://cards/data/slash.tres": 3,
	"res://cards/data/bite_down.tres": 2,
	"res://cards/data/brace.tres": 2,
	"res://cards/data/reckoning.tres": 1,
	"res://cards/data/down_payment.tres": 1,
}

@export var turn_draw_amount: int = 5
@export var player_max_hp: int = 70
@export var enemy_head_height: float = 1.8
# Where a SELF/NONE card's play tween aims, relative to the viewport's own
# center - there's no "target" to unproject for those, just somewhere up
# and away from the hand.
@export var self_play_screen_offset: Vector2 = Vector2(0.0, -250.0)

var deck: Deck
var player: Combatant
var enemies: Array[FieldEnemy] = []
var cards_played_this_turn: int = 0

var _hand_container: HandContainer
var _pending_card_view: CardView = null
var _hovered_enemy: FieldEnemy = null
var _combatants: Dictionary = {} # FieldEnemy -> Combatant
var _effect_resolver := EffectResolver.new()

func setup(hand_container: HandContainer, enemy_list: Array[FieldEnemy]) -> void:
	_hand_container = hand_container
	enemies = enemy_list

	player = Combatant.new(player_max_hp)
	player.energy = player.max_energy

	_combatants.clear()
	var enemy_names: Array[String] = []
	for enemy in enemies:
		var data: EnemyData = enemy.enemy_data
		var combatant := Combatant.new(data.max_hp if data != null else 1)
		if data != null:
			EnemyTurn.pick_initial_intent(combatant, data)
			enemy_names.append(data.enemy_name)
		_combatants[enemy] = combatant

	RunLogger.log_battle_start(enemy_names)

	deck = Deck.new(_build_starting_deck())
	deck.drawn.connect(func(_card: CardData) -> void: hand_changed.emit())
	deck.discarded.connect(func(_card: CardData) -> void: hand_changed.emit())
	_hand_container.set_deck(deck)
	_hand_container.card_clicked.connect(_on_card_view_clicked)
	_hand_container.play_animation_finished.connect(_on_play_animation_finished)

	hp_changed.emit(player.hp, player.max_hp)
	toll_changed.emit(player.toll)
	for enemy in enemies:
		var combatant: Combatant = _combatants[enemy]
		enemy_hp_changed.emit(enemy, combatant.hp, combatant.max_hp)

	_hand_container.draw_cards(turn_draw_amount)

func is_awaiting_target() -> bool:
	return _pending_card_view != null

func request_play(card_view: CardView) -> void:
	if _pending_card_view != null or card_view.card_data == null:
		return
	var card: CardData = card_view.card_data
	if card.cost > player.energy:
		return
	if card.target_type == CardData.TargetType.ENEMY:
		_pending_card_view = card_view
		card_view.lift_and_hold()
		target_requested.emit(card)
	else:
		_resolve_play(card_view, null)

func confirm_target(enemy: FieldEnemy) -> void:
	if _pending_card_view == null:
		return
	var card_view := _pending_card_view
	_pending_card_view = null
	_clear_hover()
	_resolve_play(card_view, enemy)

func cancel_target() -> void:
	if _pending_card_view == null:
		return
	_pending_card_view.release()
	_pending_card_view = null
	_clear_hover()
	target_cancelled.emit()

func end_turn() -> void:
	_hand_container.discard_hand()
	player.rally_pool = 0
	_run_enemy_turn()
	if not _check_battle_end():
		_start_player_turn()

func _resolve_play(card_view: CardView, target_enemy: FieldEnemy) -> void:
	var card: CardData = card_view.card_data
	player.energy -= card.cost

	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = _combatants.get(target_enemy)
	ctx.enemies = _living_enemy_combatants()
	ctx.deck = deck
	ctx.cards_played_this_turn = cards_played_this_turn
	ctx.rally_window = RallyWindow.new()
	ctx.on_damage = func(target_combatant: Combatant, amount: int, kind: String) -> void:
		_report_damage("player", target_combatant, amount, kind)

	RunLogger.log_card_played(card.card_name)
	_effect_resolver.resolve_card(card, ctx)
	cards_played_this_turn += 1

	toll_changed.emit(player.toll)
	status_changed.emit()

	card_played.emit(card, target_enemy)
	_hand_container.play_card(card, _screen_pos_for(target_enemy))

	_check_battle_end()

func _on_play_animation_finished(card: CardData) -> void:
	match card.removal_scope:
		CardData.RemovalScope.NONE:
			deck.discard(card)
		_:
			deck.exhaust(card)

func _run_enemy_turn() -> void:
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0:
			continue
		var data: EnemyData = enemy.enemy_data
		if data == null:
			continue
		var result := EnemyTurn.take_turn(combatant, data, player)
		if result["attacked"] and result["damage_to_hp"] > 0:
			RunLogger.log_damage_taken(result["damage_to_hp"])
			_report_damage(enemy, player, result["damage_to_hp"], "attack")
		status_changed.emit()
		if player.hp <= 0:
			break

	player.took_damage_last_turn = player.took_damage_this_turn
	player.took_damage_this_turn = false
	toll_changed.emit(player.toll)

func _start_player_turn() -> void:
	player.block = 0
	player.energy = player.max_energy
	cards_played_this_turn = 0

	Status.tick_all(player.statuses, func(amount: int) -> void:
		var lost := DamagePipeline.apply_bypass(amount, player)
		if lost > 0:
			player.toll += lost
			hp_changed.emit(player.hp, player.max_hp)
			toll_changed.emit(player.toll)
	)
	Status.remove_expired(player.statuses)
	status_changed.emit()

	if not _check_battle_end():
		_hand_container.draw_cards(turn_draw_amount)

func _check_battle_end() -> bool:
	if player.hp <= 0:
		RunLogger.log_battle_end("defeat", player.energy)
		battle_lost.emit()
		return true
	if _living_enemy_combatants().is_empty():
		RunLogger.log_battle_end("victory", player.energy)
		battle_won.emit()
		return true
	return false

func _living_enemy_combatants() -> Array[Combatant]:
	var living: Array[Combatant] = []
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant != null and combatant.hp > 0:
			living.append(combatant)
	return living

# source/target_combatant identify who dealt/received the hit; the
# emitted signal reports the FieldEnemy/"player" pair the view actually
# understands, and also fans out into hp_changed/enemy_hp_changed so the
# overlay never has to re-derive HP from a damage event itself.
func _report_damage(source: Variant, target_combatant: Combatant, amount: int, kind: String) -> void:
	RunLogger.log_damage_dealt(amount)
	if target_combatant == player:
		damage_dealt.emit(source, "player", amount, kind)
		hp_changed.emit(player.hp, player.max_hp)
	else:
		var enemy := _field_enemy_for(target_combatant)
		damage_dealt.emit(source, enemy, amount, kind)
		if enemy != null:
			enemy_hp_changed.emit(enemy, target_combatant.hp, target_combatant.max_hp)

func _field_enemy_for(combatant: Combatant) -> FieldEnemy:
	for enemy in _combatants:
		if _combatants[enemy] == combatant:
			return enemy
	return null

func _screen_pos_for(target: FieldEnemy) -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if target != null and camera != null:
		return camera.unproject_position(target.global_position + Vector3.UP * enemy_head_height)
	var overlay := get_parent() as Control
	var overlay_size: Vector2 = overlay.size if overlay != null else Vector2.ZERO
	return overlay_size / 2.0 + self_play_screen_offset

func _on_card_view_clicked(card_view: CardView) -> void:
	request_play(card_view)

# Gated on awaiting-target: this controller only reacts to input while a
# card is armed and waiting for an enemy click, everything else (movement,
# camera, ...) is untouched - and already frozen by RegionField anyway.
func _unhandled_input(event: InputEvent) -> void:
	if _pending_card_view == null:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_target()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var enemy := _raycast_enemy(event.position)
			if enemy != null:
				confirm_target(enemy)
				get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_target()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion:
		_update_hover(event.position)

func _update_hover(screen_pos: Vector2) -> void:
	var enemy := _raycast_enemy(screen_pos)
	if enemy == _hovered_enemy:
		return
	_clear_hover()
	_hovered_enemy = enemy
	if _hovered_enemy != null:
		_hovered_enemy.set_highlight(true)

func _clear_hover() -> void:
	if _hovered_enemy != null:
		_hovered_enemy.set_highlight(false)
		_hovered_enemy = null

func _raycast_enemy(screen_pos: Vector2) -> FieldEnemy:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var space_state := get_viewport().get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var collider: Object = result.get("collider")
	for enemy in enemies:
		if collider == enemy:
			return enemy
	return null

func _build_starting_deck() -> Array[CardData]:
	var cards: Array[CardData] = []
	for path: String in STARTER_DECK_COUNTS:
		var base_card: CardData = load(path) as CardData
		var copies: int = int(STARTER_DECK_COUNTS[path])
		for i in copies:
			cards.append(base_card.duplicate() as CardData)
	return cards
