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
# Fires swing_lead_seconds before card_impact for a card with a
# battle_animation - the moment the blade's whoosh starts (see Wanderer.
# _on_card_swing()), so the enemy's contact crack lands that far after
# the swing's onset. Clamped to the impact delay itself: a card whose
# delay is shorter than the lead swings at its play instant.
signal card_swing(card: CardData)
signal hand_changed()
signal target_requested(card: CardData)
signal target_cancelled()

# --- Rules-facing signals - the overlay/FloatingNumber react to these only. ---
signal hp_changed(current: int, max_hp: int)
# The player's energy after anything that changes it (setup, a card
# played, a turn start) - HandContainer fades what can't be afforded.
signal energy_changed(current: int)
signal toll_changed(new_toll: int)
# Grace opened, spent or lost - the HP bar's pale segment follows this.
signal grace_changed(grace: int)
# The player's stance was taken, deepened, replaced or expired. Carries
# the live Stance (null when none) - the stance row and the card faces
# both re-read from it.
signal stance_changed(stance: Stance)
signal status_changed()
# False the moment end_turn() commits (the enemy turn is running), true
# again once the next player turn has started - BattleOverlay disables
# End Turn in between. Not emitted by setup(): the fight opens on the
# player's turn.
signal turn_phase_changed(player_turn: bool)
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
# See card_swing.
@export var swing_lead_seconds: float = 0.04
@export var enemy_head_height: float = 1.8
# Where a SELF/NONE card's play tween aims, relative to the viewport's own
# center - there's no "target" to unproject for those, just somewhere up
# and away from the hand.
@export var self_play_screen_offset: Vector2 = Vector2(0.0, -250.0)
# Padding around each enemy's projected model rect for the armed-card
# target test - see _refresh_enemy_rects().
@export var target_padding_px: float = 16.0

var deck: Deck
var player: Combatant
var enemies: Array[FieldEnemy] = []
var cards_played_this_turn: int = 0

var _hand_container: HandContainer
var _pending_card_view: CardView = null
var _hovered_enemy: FieldEnemy = null
var _enemy_rects: Dictionary = {} # FieldEnemy -> Rect2, see _refresh_enemy_rects()
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
	player.has_grace = RunState.character.has_grace
	player.grace_cap_mode = RunState.character.grace_cap_mode
	player.grace_window_turns = RunState.character.grace_window_turns
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
# (for its on-screen top-center) and the currently hovered enemy plus its
# screen rect (see get_hovered_enemy_rect()) but shouldn't own or
# duplicate this controller's own targeting state.
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
	_enemy_rects.clear()
	_resolve_play(card_view, enemy)

func cancel_target() -> void:
	if _pending_card_view == null:
		return
	_pending_card_view.release()
	_pending_card_view = null
	_clear_hover()
	_enemy_rects.clear()
	target_cancelled.emit()

func end_turn() -> void:
	if _input_locked:
		return
	_input_locked = true
	turn_phase_changed.emit(false)
	_hand_container.discard_hand()
	_close_grace_window()
	# A stance with a duration ages on the player's own turn ending, the
	# same beat Grace closes on.
	if Stance.tick(player):
		stance_changed.emit(player.stance)
	await _run_enemy_turn()
	_input_locked = false
	if not _check_battle_end():
		_start_player_turn()
		turn_phase_changed.emit(true)

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
	# Counted at commit, before anyone hears of the play - so a face that
	# re-reads itself on card_played sees this card as played. The card's
	# own context carries the count from before it (below).
	cards_played_this_turn += 1

	RunLogger.log_card_played(card.card_name)
	card_played.emit(card, target_enemy)
	_hand_container.play_card(card, _screen_pos_for(target_enemy))

	var delay := _impact_delay_for(card)
	if delay > 0.0:
		var lead: float = clampf(swing_lead_seconds, 0.0, delay)
		if delay - lead > 0.0:
			await get_tree().create_timer(delay - lead).timeout
		if card.battle_animation != &"":
			card_swing.emit(card)
		if lead > 0.0:
			await get_tree().create_timer(lead).timeout

	card_impact.emit(card)

	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = _combatants.get(target_enemy)
	ctx.enemies = _living_enemy_combatants()
	ctx.deck = deck
	ctx.cards_played_before_this = cards_played_this_turn - 1
	ctx.on_grace_reclaimed = _on_grace_reclaimed
	ctx.on_heal = _on_card_heal
	ctx.on_damage = func(target_combatant: Combatant, amount: int, kind: String) -> void:
		_report_damage("player", target_combatant, amount, kind)

	_effect_resolver.resolve_card(card, ctx)
	# Taken, deepened or replaced by the card just played - and the card
	# faces need to know either way, since a stance changes what the hand
	# says it will do.
	stance_changed.emit(player.stance)

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
			if result["grace_opened"] > 0:
				RunLogger.log_grace_opened(result["grace_opened"], player.grace)
				grace_changed.emit(player.grace)
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

# This enemy's current block, for its EnemyStatus's segment - read by
# BattleOverlay on status_changed. 0 for a dead/unknown enemy.
func get_enemy_block(enemy: FieldEnemy) -> int:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0:
		return 0
	return combatant.block

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
# Grace spent: the rules layer has already taken it off player.grace and
# put it back on player.hp (see EffectContext.grace_reclaim()); this
# mirrors it onto the run's own HP and tells the readouts. Through
# RunState.heal(), which touches HP and nothing else - Toll accrues only
# from SELF-inflicted loss (status ticks, SELF_DAMAGE, SELF_DAMAGE_TOLL),
# so reclaiming cannot generate Toll or undo any.
# A card put HP back. Mirrored onto the run's own HP the same way a loss
# is - RunState.heal() touches HP and nothing else, so this generates no
# Toll and undoes none.
func _on_card_heal(amount: int) -> void:
	RunState.heal(amount)
	hp_changed.emit(player.hp, player.max_hp)

func _on_grace_reclaimed(amount: int) -> void:
	RunState.heal(amount)
	RunLogger.log_grace_reclaimed(amount, player.grace)
	hp_changed.emit(player.hp, player.max_hp)
	grace_changed.emit(player.grace)

# End of the player's turn: the window ages, and whatever Grace is left
# when it runs out is gone. Runs BEFORE the enemy turn (see end_turn()),
# so the hits that are about to land open a fresh window rather than
# topping up a spent one.
func _close_grace_window() -> void:
	if player.grace <= 0:
		player.grace_turns_left = 0
		return
	player.grace_turns_left -= 1
	if player.grace_turns_left > 0:
		return
	RunLogger.log_grace_lost(player.grace)
	player.grace = 0
	grace_changed.emit(0)

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
			var enemy := _enemy_at(event.position)
			if enemy != null:
				confirm_target(enemy)
				get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_target()
		get_viewport().set_input_as_handled()
		return

# The target-under-cursor test runs every physics frame while a card is
# armed (not on mouse motion): the rects move with the camera swing and
# the enemies' own lunges, so a still cursor has to re-evaluate too, and
# motion a card's own Control swallowed never has to reach this node.
func _physics_process(_delta: float) -> void:
	if _pending_card_view == null:
		return
	_refresh_enemy_rects()
	_update_hover(get_viewport().get_mouse_position())

func _update_hover(screen_pos: Vector2) -> void:
	var enemy := _enemy_at(screen_pos)
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

# Each living enemy's screen-space bounding rect of its model's world
# AABB (FieldEnemy.get_screen_rect() - the real mesh bounds, as placed,
# padded by target_padding_px on every side). No physics shape, no
# camera-distance dependence - what you can see is what you can target,
# plus a little. Recomputed by _physics_process() while a card is armed;
# _enemy_at() reads the cache. An enemy whose AABB reaches behind the
# camera gets no rect.
func _refresh_enemy_rects() -> void:
	_enemy_rects.clear()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0:
			continue
		var rect: Rect2 = enemy.get_screen_rect(camera, target_padding_px)
		if rect.size == Vector2.ZERO:
			continue
		_enemy_rects[enemy] = rect

# The enemy whose padded rect holds screen_pos; on overlap, the one
# nearest the camera. Rebuilds the cache if a click lands before the
# first armed physics frame.
func _enemy_at(screen_pos: Vector2) -> FieldEnemy:
	if _enemy_rects.is_empty():
		_refresh_enemy_rects()
	var camera := get_viewport().get_camera_3d()
	var best: FieldEnemy = null
	var best_distance: float = INF
	for enemy: FieldEnemy in _enemy_rects:
		var rect: Rect2 = _enemy_rects[enemy]
		if not rect.has_point(screen_pos):
			continue
		var distance: float = camera.global_position.distance_to(enemy.global_position) if camera != null else 0.0
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best

# The hovered enemy's padded screen rect (see _refresh_enemy_rects()) -
# TargetLine ends at its centre. Empty when nothing is hovered.
func get_hovered_enemy_rect() -> Rect2:
	if _hovered_enemy == null:
		return Rect2()
	return _enemy_rects.get(_hovered_enemy, Rect2())
