extends Node
class_name BattleController

signal card_played(card: CardData, target: FieldEnemy)
signal hand_changed()
signal target_requested(card: CardData)
signal target_cancelled()

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
@export var enemy_head_height: float = 1.8
# Where a SELF/NONE card's play tween aims, relative to the viewport's own
# center - there's no "target" to unproject for those, just somewhere up
# and away from the hand.
@export var self_play_screen_offset: Vector2 = Vector2(0.0, -250.0)

var deck: Deck
var enemies: Array[FieldEnemy] = []

var _hand_container: HandContainer
var _pending_card_view: CardView = null
var _hovered_enemy: FieldEnemy = null

func setup(hand_container: HandContainer, enemy_list: Array[FieldEnemy]) -> void:
	_hand_container = hand_container
	enemies = enemy_list

	deck = Deck.new(_build_starting_deck())
	deck.drawn.connect(func(_card: CardData) -> void: hand_changed.emit())
	deck.discarded.connect(func(_card: CardData) -> void: hand_changed.emit())
	_hand_container.set_deck(deck)
	_hand_container.card_clicked.connect(_on_card_view_clicked)
	_hand_container.play_animation_finished.connect(_on_play_animation_finished)

	_hand_container.draw_cards(turn_draw_amount)

func is_awaiting_target() -> bool:
	return _pending_card_view != null

func request_play(card_view: CardView) -> void:
	if _pending_card_view != null or card_view.card_data == null:
		return
	var card: CardData = card_view.card_data
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
	_hand_container.draw_cards(turn_draw_amount)

func _resolve_play(card_view: CardView, target: FieldEnemy) -> void:
	var card: CardData = card_view.card_data
	var target_screen_pos: Vector2 = _screen_pos_for(target)
	print("Played %s on %s" % [card.card_name, str(target.enemy_id) if target != null else "self"])
	card_played.emit(card, target)
	_hand_container.play_card(card, target_screen_pos)

func _on_play_animation_finished(card: CardData) -> void:
	deck.discard(card)

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
