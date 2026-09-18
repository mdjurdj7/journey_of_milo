extends Node
class_name BattleController

# --- View-facing input/targeting signals (unchanged from the previous pass) ---
signal card_played(card: CardData, target: FieldEnemy)
# Fires once _resolve_play()'s own impact delay has elapsed - the instant
# the swing (or, with no battle_animation, the play itself) actually
# lands - for feedback that cares about the moment of impact but not the
# damage numbers themselves (see Wanderer._on_card_impact(), the slash
# sound). damage_dealt below already fires at this same moment for
# anything that does care about the numbers.
signal card_impact(card: CardData)
signal hand_changed()
signal target_requested(card: CardData)
signal target_cancelled()

# --- Rules-facing signals - the overlay/FloatingNumber react to these only. ---
signal hp_changed(current: int, max_hp: int)
# The player's energy after anything that changes it (setup, a card
# played, a turn start) - HandContainer fades what can't be afforded.
signal energy_changed(current: int)
signal toll_changed(new_toll: int)
signal status_changed()
signal enemy_hp_changed(enemy: FieldEnemy, current: int, max_hp: int)
# The intent display's two signals. enemy_intent_changed carries
# EnemyTurn.preview_intent()'s dictionary for that enemy's QUEUED action
# (empty = nothing to show) - emitted for every living enemy after
# setup(), after every card resolves and at each player-turn start (the
# preview depends on the player's block/statuses, which those change),
# and for one enemy right after it has resolved its action, so the
# display always shows the NEXT action. enemy_acting fires just before an
# enemy resolves, so the display can hide while it acts.
signal enemy_intent_changed(enemy: FieldEnemy, preview: Dictionary)
signal enemy_acting(enemy: FieldEnemy)
signal damage_dealt(source: Variant, target: Variant, amount: int, kind: String)
# source/target are each either the String "player" or a FieldEnemy node -
# whichever combatant actually dealt/received the hit.
signal battle_won()
signal battle_lost()

@export var turn_draw_amount: int = 5
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
# Read-only from here on: the Wanderer whose clip lengths _impact_delay_
# for() clamps against, and whose play_attack_snap() timing _run_enemy_
# turn() awaits. Set once, in setup().
var _wanderer: Wanderer = null
# True from the moment a card commits to playing (or a turn ends) until
# its own impact/enemy-turn delay has fully resolved - request_play() and
# end_turn() both refuse to start anything new while this is true, so a
# second card/turn can never be armed mid-swing.
var _input_locked: bool = false

func setup(hand_container: HandContainer, enemy_list: Array[FieldEnemy], wanderer: Wanderer) -> void:
	_hand_container = hand_container
	enemies = enemy_list
	_wanderer = wanderer

	player = Combatant.new(RunState.player_max_hp)
	player.hp = RunState.player_hp
	player.rally_recovery_percent = RunState.character.rally_recovery_percent
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

	deck = Deck.new(RunState.deck)
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

	energy_changed.emit(player.energy)
	_hand_container.draw_cards(turn_draw_amount)
	_emit_intent_previews()

# The queued action of one enemy as the display should show it - see
# EnemyTurn.preview_intent(). Empty for a dead/unknown enemy.
func get_intent_preview(enemy: FieldEnemy) -> Dictionary:
	var combatant: Combatant = _combatants.get(enemy)
	var data: EnemyData = enemy.enemy_data if enemy != null else null
	if combatant == null or data == null or combatant.hp <= 0:
		return {}
	return EnemyTurn.preview_intent(combatant, data, player)

func _emit_intent_previews() -> void:
	for enemy in enemies:
		enemy_intent_changed.emit(enemy, get_intent_preview(enemy))

func is_awaiting_target() -> bool:
	return _pending_card_view != null

# Read-only access for TargetLine, which needs the armed card's own view
# (for its on-screen top-center) and the currently hovered enemy (for its
# chest position) but shouldn't own or duplicate this controller's own
# targeting state.
func get_pending_card_view() -> CardView:
	return _pending_card_view

func get_hovered_enemy() -> FieldEnemy:
	return _hovered_enemy

func request_play(card_view: CardView) -> void:
	if _input_locked or _pending_card_view != null or card_view.card_data == null:
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
	if _input_locked:
		return
	_input_locked = true
	_hand_container.discard_hand()
	player.rally_pool = 0
	await _run_enemy_turn()
	_input_locked = false
	if not _check_battle_end():
		_start_player_turn()

# card_played fires first (so the swing/fly-out animation starts
# immediately), then this awaits the card's own impact delay - min(card.
# impact_time, the clip's real length so a shorter clip still fires at
# its own end) - before resolving a single effect, 0 with no battle_
# animation at all. Every existing consumer of the signals below
# (damage_dealt, hp_changed, enemy_hp_changed, RunState.lose_hp, the
# floating number, HP bars) already reacts to whichever of them fires
# once resolve_card() actually runs, so all of that lands in sync with
# the swing with no rewiring - only the wait moved. _input_locked (set
# by the caller path this always runs on) keeps a second card from being
# armed while this is in flight.
func _resolve_play(card_view: CardView, target_enemy: FieldEnemy) -> void:
	var card: CardData = card_view.card_data
	player.energy -= card.cost
	_input_locked = true

	RunLogger.log_card_played(card.card_name)
	card_played.emit(card, target_enemy)
	_hand_container.play_card(card, _screen_pos_for(target_enemy))

	var delay := _impact_delay_for(card)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	card_impact.emit(card)

	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = _combatants.get(target_enemy)
	ctx.enemies = _living_enemy_combatants()
	ctx.deck = deck
	ctx.cards_played_this_turn = cards_played_this_turn
	ctx.rally_window = RallyWindow.new()
	ctx.on_damage = func(target_combatant: Combatant, amount: int, kind: String) -> void:
		_report_damage("player", target_combatant, amount, kind)

	_effect_resolver.resolve_card(card, ctx)
	cards_played_this_turn += 1

	toll_changed.emit(player.toll)
	status_changed.emit()
	energy_changed.emit(player.energy)
	# Block/statuses may have moved - the previews' modified numbers and
	# lethal flags follow.
	_emit_intent_previews()

	_input_locked = false
	_check_battle_end()

# CardData.impact_time's own clamp: a clip shorter than the authored
# impact_time fires at the clip's own end instead of after it's already
# finished. _wanderer is only used to look up that length - if it's ever
# unset, the authored impact_time is used unclamped rather than dropped
# to 0.
func _impact_delay_for(card: CardData) -> float:
	if card.battle_animation == &"":
		return 0.0
	var delay: float = card.impact_time
	if _wanderer != null:
		var clip_length: float = _wanderer.get_clip_length(card.battle_animation)
		if clip_length > 0.0:
			delay = minf(delay, clip_length)
	return delay

func _on_play_animation_finished(card: CardData) -> void:
	match card.removal_scope:
		CardData.RemovalScope.NONE:
			deck.discard(card)
		_:
			deck.exhaust(card)

# Same shape as _resolve_play()'s own await: EnemyTurn.take_turn() has
# already mutated combatant/player HP synchronously by the time this
# awaits anything (rules stay instant), but the report - and everything
# that reacts to it - waits for enemy.play_attack_snap()'s own return
# value, the point in its forward lunge that counts as "landed". Creatures
# have no clips to sync to (see FieldEnemy.play_attack_snap()'s own doc),
# so that snap is this loop's equivalent of a card's battle_animation.
# Runs regardless of whether the attack actually did any damage (a fully
# blocked attack still visibly lunges), the report itself only fires with
# damage_to_hp > 0, same as before.
func _run_enemy_turn() -> void:
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0:
			continue
		var data: EnemyData = enemy.enemy_data
		if data == null:
			continue
		enemy_acting.emit(enemy)
		var result := EnemyTurn.take_turn(combatant, data, player)
		if result["attacked"]:
			var snap_delay: float = enemy.play_attack_snap(_wanderer)
			if snap_delay > 0.0:
				await get_tree().create_timer(snap_delay).timeout
			if result["damage_to_hp"] > 0:
				RunLogger.log_damage_taken(result["damage_to_hp"])
				_report_damage(enemy, player, result["damage_to_hp"], "attack")
		status_changed.emit()
		# take_turn() has already advanced this enemy to its next intent -
		# show it the moment this action has landed.
		enemy_intent_changed.emit(enemy, get_intent_preview(enemy))
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
			RunState.lose_hp(lost)
			hp_changed.emit(player.hp, player.max_hp)
			toll_changed.emit(player.toll)
	)
	Status.remove_expired(player.statuses)
	status_changed.emit()
	energy_changed.emit(player.energy)
	# Block just reset to 0 and statuses ticked: lethal flags change here.
	_emit_intent_previews()

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
		RunState.lose_hp(amount)
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
