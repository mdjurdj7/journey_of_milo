extends Control
class_name HandContainer

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"

# How far above its normal arc position a hovered/armed card gets raised
# in draw order - just needs to clear the largest realistic hand z_index
# (one per card), not tied to card count itself.
const HOVER_Z_INDEX := 1000
# Above even a hovered card.
const ARMED_Z_INDEX := 1001

signal card_clicked(card_view: CardView)
signal play_animation_finished(card_data: CardData)
# A card was lifted into the armed position / returned or played from it -
# BattleOverlay disables End Turn while one is armed.
signal armed_changed(armed: bool)
# The card whose cost the energy readout previews changed: the armed card
# if there is one, else the hovered one - never a card that is only
# marked (a Bide or Deny choice) - or null for none.
signal cost_focus_changed(card_data: CardData)
# A drawn card has left the deck - its arrival flight has just begun
# (see _launch_arrival()). Once per card, staggered as the flights are.
signal draw_started(card_data: CardData)

# Must match CardView.card_size (200 x 280 at 1x).
@export var card_size: Vector2 = Vector2(200.0, 280.0)
# Display scale for every card in the hand while the row fits between
# the limits at it - below it only once the gap has closed to hand_min_
# gap_px (see _row_fit()), same "smaller than full card_size for this
# context" role DeckView's own deck_view_card_scale plays there.
@export_range(0.1, 1.0) var hand_card_scale: float = 0.95:
	set(value):
		hand_card_scale = value
		_reflow_hand(false)
# How long a card's own slot takes to glide to its new arc position/
# rotation when the hand's composition changes (draw/discard reflowing
# every other card to make room or close the gap) - the one genuinely new
# timing this feature adds; every other duration here predates it.
@export var reflow_duration_sec: float = 0.15

# At rest, a card's slot-space offset is card_size.y minus this (see
# CardView.set_rest_offset()) - and since a hand card scales about its
# bottom centre, its rendered top is that offset plus card_size.y * (1 -
# hand_card_scale) further down. 182 with the overlay's container (top
# at 1080 - 365 = 715, arc 22) and hand_card_scale 0.95 puts the centre
# card's top at y 805 (0.75 of 1080), its bottom 9px inside the viewport;
# the outer cards sit the full arc (22px) lower and lean +-4 deg, which
# drops their rules line's low corner another ~6px - the number is set so
# that corner (rules box ends 243 x 0.95 = 231px down the card) still
# clears the viewport's bottom edge by ~16px, and only the outer cards'
# footer rule and type label are cut. CardView.hover_lift is measured
# from this baseline.
@export var hand_rest_visible_height: float = 182.0:
	set(value):
		hand_rest_visible_height = value
		for card_view in _card_views():
			card_view.set_rest_offset(card_size.y - hand_rest_visible_height)

# The row's bounds, viewport x: its rightmost card's drawn edge never
# right of hand_right_limit_x (clear of END TURN and the DISCARD line,
# whose left edges sit at 1799 and 1804+ at 1080p), its leftmost's never
# left of hand_left_limit_x - the mirror of it (1920 - 1775), so the row,
# centred between them, is centred on the screen. See _row_fit() for what
# gives when it doesn't fit.
@export var hand_left_limit_x: float = 145.0:
	set(value):
		hand_left_limit_x = value
		_reflow_hand(false)
@export var hand_right_limit_x: float = 1775.0:
	set(value):
		hand_right_limit_x = value
		_reflow_hand(false)
# The narrowest edge gap the row closes to before its cards shrink.
@export var hand_min_gap_px: float = 4.0:
	set(value):
		hand_min_gap_px = value
		_reflow_hand(false)

@export_group("Fan")
# Gap between adjacent cards' edges while the row fits between the limits
# at it - see _row_fit(). Cards never overlap.
@export var fan_gap: float = 12.0:
	set(value):
		fan_gap = value
		_reflow_hand(false)
# Outer cards tilt outward by up to this many degrees - 0 at the hand's
# own center, ±this at its two ends (see _reflow_hand()'s own t/rotation
# math). First-pass numbers, all three below - untested without running
# the game; retune live once seen.
@export var fan_max_rotation_degrees: float = 4.0:
	set(value):
		fan_max_rotation_degrees = value
		_reflow_hand(false)
# How much higher the center of the hand sits than its two ends - a
# parabola through (t=-1, 0), (t=0, this), (t=1, 0), same t as rotation
# above.
@export var fan_arc_height: float = 22.0:
	set(value):
		fan_arc_height = value
		_reflow_hand(false)

@export_group("Draw")
# A drawn card flies from the DECK readout (set_draw_origin()) into its
# slot over this long, one ease-out, growing from draw_start_scale of its
# hand size and fading in; the rest of the hand makes room over the same
# time. Read at each launch, so a Remote-tab edit applies from the next
# draw.
@export var draw_duration: float = 0.22
# Between one drawn card's launch and the next's - a turn's draw, or a
# draw effect's, comes out one card at a time.
@export var draw_stagger: float = 0.07
# A drawn card's size at the DECK readout, as a fraction of its hand size.
@export_range(0.05, 1.0) var draw_start_scale: float = 0.4

@export_group("Play Fade")
# A played card fades out where it is - the armed pose, centre - over
# this long, its scale easing down to play_fade_end_scale, and goes
# toward no pile. It starts with the card-play sound (the same frame).
@export var play_fade_duration: float = 0.16
# The played card's last scale, on the same footing as CardView.armed_
# scale (1.2): an armed card ends at exactly this, any other at the same
# fraction of where it started.
@export var play_fade_end_scale: float = 1.12
# When the played card leaves deck.hand for its pile (play_animation_
# finished) - the old fly-out's 0.25 + 0.2 s, kept apart from the fade so
# the rules see the card in hand exactly as long as before (see DESIGN.md,
# Deferred). The DISCARD readout ticks then.
@export var play_settle_sec: float = 0.45

@export_group("Leave Fade")
# Every card leaving the hand but a played one (which has its own fade
# above) - a discard, a set-aside, the end-of-turn discard - fades out in
# place over this long, sinking discard_fade_sink_px. The end-of-turn
# discard's cards go one after another discard_fade_stagger apart, and
# the enemy turn waits for the last (discard_hand() returns how long).
@export var discard_fade_duration: float = 0.16
@export var discard_fade_stagger: float = 0.03
@export var discard_fade_sink_px: float = 6.0

var _deck: Deck = null
# The hand's slots in hand order, each a Control whose only child is a
# CardView, and the card each shows. An ARRAY, not a map keyed by
# CardData: the deck can hold one CardData twice (a reward taken twice
# used to be the same resource appended twice), and a map lost the
# first slot the moment the second was drawn - an orphan stuck at its
# last arc position, never reflowed or removed. Both structures are
# only ever written by _sync_with_deck(), play_card() and _forget_slot().
var _slots: Array[Control] = []
var _slot_cards: Dictionary = {} # Control (slot) -> CardData
# Each slot's running reflow glide, so the next reflow retargets it
# rather than racing it - see _reflow_hand().
var _reflow_tweens: Dictionary = {} # Control (slot) -> Tween
# The player's current energy, as last pushed by update_playable() - a
# card drawn later is faded or not against this same number.
# The stance every card in this hand is currently printed against.
var _stance: Stance = null
var _grace: int = 0
var _toll: int = 0
# The battle state the cards' conditionals are read against - see
# set_bonus_context(). Null until the overlay's first push.
var _bonus_context: EffectContext = null
var _last_energy: int = -1
# Set by BattleController - see set_enemy_target_available().
var _enemy_target_available: bool = true
# Where a drawn card's flight starts: the battle's DECK readout, its
# centre read at each launch - see set_draw_origin().
var _draw_origin: Control = null
# Cards the Deck has just drawn, not yet given a view - _sync_with_deck()
# gives these an arrival flight; any other new card (a set-aside card
# back, the F1 row's Add card) appears in place.
var _arriving_cards: Array[CardData] = []
# Drawn slots waiting their turn to launch: in _slots (the hand holds
# them) but left out of the layout and unseen until _launch_arrival().
var _waiting_slots: Dictionary = {} # Control (slot) -> true
# Each flying slot's scale/fade tween - its position and rotation glide
# is a reflow tween like any other, so a reflow mid-flight retargets it.
var _arrival_tweens: Dictionary = {} # Control (slot) -> Tween
# When the next drawn card may launch (Time.get_ticks_msec()) - the
# stagger runs on across draws that come close together.
var _next_launch_msec: int = 0
# Set by discard_hand() while the Deck discards: the slots that go then
# fade in place (_fade_and_remove()) the Nth after N stagger steps, not
# all at once.
var _fading_discard: bool = false
var _fade_index: int = 0

# No longer a Container (HBoxContainer defaulted this to IGNORE on its
# own) - the arc leaves real gaps between/around fanned cards where the
# battle scene behind should stay clickable, same reasoning BattleOverlay
# itself already sets this for.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The arc is centred on this control's own width.
	resized.connect(func() -> void: _reflow_hand(false))

# This slot's own current arc target - read back by _on_card_lowered() to
# know what to return to (_reflow_hand() may have moved the target while
# the card was lifted, since a reflow keeps updating these for every slot
# regardless of lift state - see that function's own doc).
var _arc_positions: Dictionary = {} # Control (slot) -> Vector2
var _arc_rotations: Dictionary = {} # Control (slot) -> float degrees
var _arc_z_indices: Dictionary = {} # Control (slot) -> int
# Slots currently hovered - _reflow_hand() skips touching a lifted slot's
# own rotation/z_index (position still updates, so the rest of the hand
# can shift around it), leaving CardView's own lift signal handlers as
# the only thing driving those two properties until lowered.
var _lifted_slots: Dictionary = {} # Control (slot) -> true
# The one armed slot, if any: left out of the fan entirely (the hand
# closes under it) and parked at the card's armed_position until
# disarmed - see _on_card_armed()/_on_card_disarmed().
var _armed_slot: Control = null
# The card cost_focus_changed last named (null: none).
var _focus_card: CardData = null

func set_deck(deck: Deck) -> void:
	if _deck != null:
		_deck.drawn.disconnect(_on_card_drawn)
		_deck.discarded.disconnect(_on_deck_changed)
		_deck.added.disconnect(_on_deck_changed)
		_deck.set_aside_changed.disconnect(_sync_with_deck)
	_deck = deck
	_arriving_cards.clear()
	_deck.drawn.connect(_on_card_drawn)
	_deck.discarded.connect(_on_deck_changed)
	_deck.added.connect(_on_deck_changed)
	_deck.set_aside_changed.connect(_sync_with_deck)
	_sync_with_deck()

func _on_deck_changed(_card: CardData) -> void:
	_sync_with_deck()

func _on_card_drawn(card: CardData) -> void:
	_arriving_cards.append(card)
	_sync_with_deck()

# The battle's DECK readout - where drawn cards fly in from.
func set_draw_origin(origin: Control) -> void:
	_draw_origin = origin

# A hand choice opened with `chooser` armed (BattleController's choose
# mode): the arming suppressed every other card's hover, but here they
# are what gets clicked, so hover comes back for them - for `eligible`
# alone when it names any (Deny's tie), the rest staying still. A null
# chooser is the end-of-turn keep: no card armed, the whole hand chooses.
func begin_choice(chooser: CardView, eligible: Array[CardView] = []) -> void:
	for view in _card_views():
		if view != chooser and (eligible.is_empty() or eligible.has(view)):
			view.set_hover_suppressed(false)

# The choice closed (confirmed or cancelled): every mark comes off but
# `keep`'s (Deny's pick, waiting on its target), and while a card is
# still armed the rest of the hand goes back to not hovering.
func end_choice(keep: CardView = null) -> void:
	for view in _card_views():
		if view != keep:
			view.set_marked(false)
	if _armed_slot == null:
		return
	var armed_view: CardView = _armed_slot.get_child(0) as CardView
	for view in _card_views():
		if view != armed_view:
			view.set_hover_suppressed(true)

# The chosen cards' own slots leave the hand now - called right before
# the Deck sets their cards aside, so with two copies of a card in hand
# the one that goes is the one that was marked, not whichever the sync
# would match first (play_card() takes its slot out the same way).
func release_views(views: Array[CardView]) -> void:
	for slot in _slots.duplicate():
		var view: CardView = slot.get_child(0) as CardView
		if view == null or not views.has(view):
			continue
		_slots.erase(slot)
		_slot_cards.erase(slot)
		_forget_slot(slot)
		_fade_and_remove(slot, 0.0)
	_reflow_hand()

# The one way the hand's contents change: the Deck's hand is the truth,
# and the slots are brought to match it - a slot for every card the
# hand holds (two for a card it holds twice, matched one for one), a
# fade out for every slot whose card it no longer holds, a fresh view
# for every card without one - then a single reflow. A drawn card's
# fresh view waits its turn and flies in from the DECK readout (_queue_
# arrival()); any other appears in place. Called on every
# drawn/discarded/added signal and on set_deck(); play_card() takes its own
# slot out before the Deck hears of the play, so the play's later
# discard/exhaust changes nothing here. A view is never made or dropped
# anywhere else.
func _sync_with_deck() -> void:
	if _deck == null:
		return
	var wanted: Array[CardData] = _deck.hand.duplicate()
	var kept: Array[Control] = []
	for slot in _slots:
		var card: CardData = _slot_cards.get(slot)
		var index: int = wanted.find(card)
		if index >= 0:
			wanted.remove_at(index)
			kept.append(slot)
		else:
			_slot_cards.erase(slot)
			_forget_slot(slot)
			if _fading_discard:
				_fade_and_remove(slot, discard_fade_stagger * float(_fade_index))
				_fade_index += 1
			else:
				_fade_and_remove(slot, 0.0)
	_slots = kept
	for card in wanted:
		var index: int = _arriving_cards.find(card)
		if index >= 0:
			_arriving_cards.remove_at(index)
		_add_card_view(card)
		if index >= 0:
			_queue_arrival(_slots.back())
	_reflow_hand()

func draw_cards(amount: int) -> void:
	if _deck == null:
		return
	_deck.draw(amount)

# `keep`: cards that stay in the hand (the end-of-turn keep). Every other
# card fades out in place, staggered; returns how long until the last
# has gone (0 with nothing discarded).
func discard_hand(keep: Array[CardData] = []) -> float:
	if _deck == null:
		return 0.0
	_fading_discard = true
	_fade_index = 0
	_deck.discard_hand(keep)
	_fading_discard = false
	if _fade_index == 0:
		return 0.0
	return discard_fade_duration + discard_fade_stagger * float(_fade_index - 1)

func _add_card_view(card: CardData) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = card_size

	var card_view := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	card_view.card_size = card_size
	card_view.set_stance(_stance)
	card_view.set_grace(_grace)
	card_view.set_toll(_toll)
	card_view.set_bonus_context(_bonus_context)
	slot.add_child(card_view)

	# Brings slot (and card_view within it) into the live tree, firing
	# CardView._ready() - must happen before set_card_data() below, which
	# needs card_view's @onready label references already populated.
	add_child(slot)

	card_view.set_rest_offset(card_size.y - hand_rest_visible_height)
	card_view.set_card_data(card)
	if _last_energy >= 0:
		card_view.set_playable(_can_play(card, _last_energy))
	card_view.clicked.connect(_on_card_view_clicked.bind(card_view))
	card_view.lifted.connect(_on_card_lifted.bind(slot, card_view))
	card_view.lowered.connect(_on_card_lowered.bind(slot, card_view))
	card_view.armed.connect(_on_card_armed.bind(slot, card_view))
	card_view.disarmed.connect(_on_card_disarmed.bind(slot, card_view))
	if _armed_slot != null:
		card_view.set_hover_suppressed(true)

	_slots.append(slot)
	_slot_cards[slot] = card

# A drawn slot holds, unseen and out of the layout, until its launch -
# draw_stagger after the one before it, or the next frame (the readouts
# are laid out by then). Its card takes no input until it lands.
func _queue_arrival(slot: Control) -> void:
	_waiting_slots[slot] = true
	slot.modulate.a = 0.0
	(slot.get_child(0) as CardView).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var now: int = Time.get_ticks_msec()
	var launch_at: int = maxi(now, _next_launch_msec)
	_next_launch_msec = launch_at + int(draw_stagger * 1000.0)
	get_tree().create_timer(float(launch_at - now) / 1000.0).timeout.connect(_launch_arrival.bind(slot))

# The slot joins the layout (the hand making room over draw_duration),
# then starts from the DECK readout's centre - straight, small and clear
# - and glides to its arc place, growing and fading in on the way.
func _launch_arrival(slot: Control) -> void:
	if not is_instance_valid(slot) or not _waiting_slots.has(slot):
		return
	_waiting_slots.erase(slot)
	draw_started.emit(_slot_cards.get(slot))
	# New to the layout, so this snaps it to its arc target; the others glide.
	_reflow_hand(true, draw_duration)
	if _draw_origin == null or not is_instance_valid(_draw_origin):
		_land(slot)
		return
	var target_position: Vector2 = slot.position
	var target_rotation: float = slot.rotation_degrees
	# The card's centre in slot space, then the slot placed so that centre,
	# scaled by draw_start_scale about the slot's pivot, sits on the readout.
	var card_view: CardView = slot.get_child(0) as CardView
	var card_centre: Vector2 = card_view.position + card_view.pivot_offset + (card_view.size / 2.0 - card_view.pivot_offset) * card_view.scale
	var start_global: Vector2 = _draw_origin.get_global_rect().get_center() - slot.pivot_offset - (card_centre - slot.pivot_offset) * draw_start_scale
	slot.rotation_degrees = 0.0
	slot.scale = Vector2.ONE * draw_start_scale
	slot.global_position = start_global

	var glide := create_tween()
	glide.set_ease(Tween.EASE_OUT)
	glide.set_trans(Tween.TRANS_CUBIC)
	glide.set_parallel(true)
	glide.tween_property(slot, "position", target_position, draw_duration)
	if not _lifted_slots.has(slot):
		glide.tween_property(slot, "rotation_degrees", target_rotation, draw_duration)
	_reflow_tweens[slot] = glide

	var arrival := create_tween()
	arrival.set_ease(Tween.EASE_OUT)
	arrival.set_trans(Tween.TRANS_CUBIC)
	arrival.set_parallel(true)
	arrival.tween_property(slot, "scale", Vector2.ONE, draw_duration)
	arrival.tween_property(slot, "modulate:a", 1.0, draw_duration)
	arrival.chain().tween_callback(_land.bind(slot))
	_arrival_tweens[slot] = arrival

# Landed (or cut short): full size, opaque, and its card takes input.
func _land(slot: Control) -> void:
	_arrival_tweens.erase(slot)
	slot.scale = Vector2.ONE
	slot.modulate.a = 1.0
	var card_view: CardView = slot.get_child(0) as CardView
	if card_view != null:
		card_view.mouse_filter = Control.MOUSE_FILTER_STOP

# A card still waiting or in flight that is armed or played (only the
# rules can, never the mouse) lands on the spot first, so the pose it
# takes starts from a whole card at its place in the row.
func _land_now(slot: Control) -> void:
	if not _waiting_slots.has(slot) and not _arrival_tweens.has(slot):
		return
	var tween: Tween = _arrival_tweens.get(slot)
	if tween != null and tween.is_valid():
		tween.kill()
	var was_waiting: bool = _waiting_slots.erase(slot)
	_land(slot)
	if was_waiting:
		_reflow_hand(false)

func _on_card_view_clicked(_card_data: CardData, card_view: CardView) -> void:
	card_clicked.emit(card_view)

# Global Y of a resting centre card's rendered top edge - what anything
# above the hand (the readouts; CameraRig's battle fit reads it) has to
# clear: the arc's peak slot plus the rest offset (a slot-space offset,
# unscaled), plus the height the card loses to hand_card_scale - it
# scales about its bottom centre, so the shrink comes off the top.
func get_rest_top_y() -> float:
	return global_position.y - fan_arc_height + (card_size.y - hand_rest_visible_height) + card_size.y * (1.0 - hand_card_scale)

# Fades every card the player can't currently afford (see CardView.
# set_playable()) - called on BattleController.energy_changed, and
# applied to cards drawn afterwards too.
# The stance in force, pushed down to every card in hand: an Attack's
# printed damage and its "-N HP" line both move with it, so a card that
# is sitting in the hand when a stance is taken has to be re-read, not
# just the one played next. Kept so a card drawn AFTER the stance was
# taken gets it too (see _add_card_view()).
func set_stance(stance: Stance) -> void:
	_stance = stance
	for card_view in _card_views():
		card_view.set_stance(stance)

# The player's Grace, pushed to every card for the same reason the stance
# is: a card whose damage depends on it has to say so while it sits in
# the hand.
func set_grace(grace: int) -> void:
	_grace = grace
	for card_view in _card_views():
		card_view.set_grace(grace)

# The player's Toll, for the same reason as the stance and Grace:
# Reckoning's printed damage and Debt Forgiven's printed heal are both
# made of it, and both move every time it does.
func set_toll(toll: int) -> void:
	_toll = toll
	for card_view in _card_views():
		card_view.set_toll(toll)

# The battle as it stands (BattleController.preview_context()), pushed
# by the overlay on every signal that can move a conditional - a card
# played, a turn boundary, Grace, HP, Toll - and to cards drawn
# afterwards. This is the ONLY place a CardView ever gets one, which is
# what keeps every other card on screen neutral.
func set_bonus_context(ctx: EffectContext) -> void:
	_bonus_context = ctx
	for card_view in _card_views():
		card_view.set_bonus_context(ctx)

# One face read against its own context - the armed card's, aimed at the
# enemy under the cursor (BattleOverlay._on_hovered_enemy_changed()). Not
# kept: the next set_bonus_context() puts that face back with the rest.
func set_card_bonus_context(card_view: CardView, ctx: EffectContext) -> void:
	card_view.set_bonus_context(ctx)

func update_playable(energy: int) -> void:
	_last_energy = energy
	for slot in _slots:
		var card_view: CardView = slot.get_child(0) as CardView
		var card: CardData = _slot_cards.get(slot)
		if card_view != null and card != null:
			card_view.set_playable(_can_play(card, energy))

# Whether any enemy can be targeted - false while every one is buried
# (see BattleController._push_enemy_target_available(), which sets it
# just before the energy_changed that re-reads the hand). An enemy-
# target card fades like an unaffordable one while it's false.
func set_enemy_target_available(available: bool) -> void:
	_enemy_target_available = available

func _can_play(card: CardData, energy: int) -> bool:
	if card.target_type == CardData.TargetType.ENEMY and not _enemy_target_available:
		return false
	# An enemy-target card with no enemy it may land on (Deny, every one
	# left already Denied) fades too - the same rule targeting reads.
	if card.target_type == CardData.TargetType.ENEMY and _bonus_context != null and not EffectResolver.has_target(card, _bonus_context.enemies):
		return false
	# A card the rules block - a fixed Toll not held (Come Due) - fades like
	# an unaffordable one (EffectResolver.card_blocked()). No context yet =
	# nothing to ask.
	if _bonus_context != null and EffectResolver.card_blocked(card, _bonus_context.player):
		return false
	# The fight's own reading of the cost (Combatant.energy_cost()), once
	# there's a context to ask.
	var cost: int = _bonus_context.player.energy_cost(card) if _bonus_context != null else card.cost
	return cost <= energy

# Every slot's CardView, in hand order.
func _card_views() -> Array[CardView]:
	var views: Array[CardView] = []
	for slot in _slots:
		var card_view: CardView = slot.get_child(0) as CardView
		if card_view != null:
			views.append(card_view)
	return views

# Straightens this slot to 0 rotation and brings it to the front of the
# fan - fired for both a plain hover and an armed card (CardView.lifted
# covers both, see its own doc), so a card picked out of the hand either
# way reads the same: level and on top of its neighbors.
func _on_card_lifted(slot: Control, card_view: CardView) -> void:
	_lifted_slots[slot] = true
	_refresh_cost_focus()
	slot.z_index = HOVER_Z_INDEX
	var tween := create_tween()
	tween.tween_property(slot, "rotation_degrees", 0.0, card_view.hover_duration_sec)

func _on_card_lowered(slot: Control, card_view: CardView) -> void:
	_lifted_slots.erase(slot)
	_refresh_cost_focus()
	if slot == _armed_slot:
		return
	slot.z_index = int(_arc_z_indices.get(slot, 0))
	var target_rotation: float = _arc_rotations.get(slot, 0.0)
	var tween := create_tween()
	tween.tween_property(slot, "rotation_degrees", target_rotation, card_view.hover_duration_sec)

# Armed: the slot leaves the fan (the others close the gap, animated),
# goes on top, straightens, and travels so the card's bottom centre lands
# on CardView.get_armed_bottom_centre() - the card itself scales to
# armed_scale in the same time. Every other card stops responding to
# hover until disarmed. The slot is NOT re-parented (unlike play_card()):
# it stays a child here, just parked outside the arc, so returning it is
# a plain reflow.
func _on_card_armed(slot: Control, card_view: CardView) -> void:
	_land_now(slot)
	_armed_slot = slot
	armed_changed.emit(true)
	_refresh_cost_focus()
	_lifted_slots.erase(slot)
	for other in _slots:
		var other_view: CardView = other.get_child(0) as CardView
		if other_view != null and other_view != card_view:
			other_view.set_hover_suppressed(true)
	slot.z_index = ARMED_Z_INDEX
	_reflow_hand()

	# The card's bottom centre in slot space is fixed by its pivot (bottom
	# centre) regardless of scale: position + (size/2, size).
	var card_bottom_centre_local: Vector2 = card_view.position + Vector2(card_view.size.x / 2.0, card_view.size.y)
	var target_global: Vector2 = card_view.get_armed_bottom_centre() - card_bottom_centre_local
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(slot, "rotation_degrees", 0.0, card_view.armed_duration_sec)
	tween.tween_property(slot, "global_position", target_global, card_view.armed_duration_sec)

# Disarmed (cancelled): back into the fan - the reflow re-includes the
# slot and glides it to its arc target over the same time; hover comes
# back for everyone.
func _on_card_disarmed(slot: Control, card_view: CardView) -> void:
	if _armed_slot != slot:
		return
	_armed_slot = null
	armed_changed.emit(false)
	_refresh_cost_focus()
	for other in _slots:
		var other_view: CardView = other.get_child(0) as CardView
		if other_view != null:
			other_view.set_hover_suppressed(false)
	if not _slots.has(slot):
		return
	slot.z_index = int(_arc_z_indices.get(slot, 0))
	_reflow_hand(true, card_view.armed_duration_sec)

func _forget_slot(slot: Control) -> void:
	_kill_reflow_tween(slot)
	var arrival: Tween = _arrival_tweens.get(slot)
	if arrival != null and arrival.is_valid():
		arrival.kill()
	_arrival_tweens.erase(slot)
	_waiting_slots.erase(slot)
	_arc_positions.erase(slot)
	_arc_rotations.erase(slot)
	_arc_z_indices.erase(slot)
	_lifted_slots.erase(slot)
	_refresh_cost_focus()

# Names the card whose cost the readout previews, when it changes: the
# armed card wins; else a lifted card that is hovered, not just marked.
func _refresh_cost_focus() -> void:
	var card: CardData = null
	if _armed_slot != null:
		card = _slot_cards.get(_armed_slot)
	else:
		for slot: Control in _lifted_slots:
			var view: CardView = slot.get_child(0) as CardView
			if view != null and not view.is_marked():
				card = _slot_cards.get(slot)
				break
	if card == _focus_card:
		return
	_focus_card = card
	cost_focus_changed.emit(card)

func _kill_reflow_tween(slot: Control) -> void:
	var tween: Tween = _reflow_tweens.get(slot)
	if tween != null and tween.is_valid():
		tween.kill()
	_reflow_tweens.erase(slot)

# A card's way out of the hand (but a play's): after `delay` (the
# end-of-turn discard's stagger, else 0), fades where it rests, sinking a
# few px - no travel, no pile.
func _fade_and_remove(slot: Control, delay: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_interval(delay)
	tween.tween_property(slot, "modulate:a", 0.0, discard_fade_duration)
	tween.parallel().tween_property(slot, "position:y", slot.position.y + discard_fade_sink_px, discard_fade_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_callback(slot.queue_free)

# A played card leaves the hand: it fades out where it is (see play_fade_
# duration) - discard, Spent or Consumed alike - and play_animation_
# finished, which moves it to its pile, follows play_settle_sec after the
# play, whatever the fade. `_target_screen_pos` is no longer travelled to.
func play_card(card_data: CardData, _target_screen_pos: Vector2) -> void:
	var slot: Control = null
	for candidate in _slots:
		if _slot_cards.get(candidate) == card_data:
			slot = candidate
			break
	if slot == null:
		return
	_land_now(slot)
	_slots.erase(slot)
	_slot_cards.erase(slot)
	_forget_slot(slot)
	_reflow_hand()

	var card_view: CardView = slot.get_child(0) as CardView
	card_view.mark_played()
	if _armed_slot == slot:
		_armed_slot = null
		armed_changed.emit(false)
		_refresh_cost_focus()
		for other in _slots:
			var other_view: CardView = other.get_child(0) as CardView
			if other_view != null:
				other_view.set_hover_suppressed(false)

	# Detach from the row - left parented under this Control, it would
	# collide with the reflow tween above the instant the next card is
	# drawn/discarded. Its new parent (BattleOverlay's own root Control)
	# is a plain, non-container Control, safe for free on-screen travel.
	var slot_global_pos: Vector2 = slot.global_position
	remove_child(slot)
	get_parent().add_child(slot)
	slot.global_position = slot_global_pos

	var end_scale: Vector2 = card_view.scale * (play_fade_end_scale / card_view.armed_scale)
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(slot, "modulate:a", 0.0, play_fade_duration)
	fade.tween_property(card_view, "scale", end_scale, play_fade_duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	fade.chain().tween_callback(slot.queue_free)
	# On this node, like the old fly-out: a fight torn down before it ends
	# never hears of the card, as before.
	var settle := create_tween()
	settle.tween_interval(play_settle_sec)
	settle.tween_callback(func() -> void: play_animation_finished.emit(card_data))

# Lays every current card out on an arc centred between hand_left_limit_x
# and hand_right_limit_x: each card's normalized position t (-1 at the
# leftmost card, 0 at the hand's center, +1 at the rightmost) drives both
# its rotation (t * fan_max_rotation_degrees) and its vertical lift (a
# parabola peaking at fan_arc_height when t=0, 0 at the two ends) - see
# the per-card loop below. The card scale and edge gap, uniform across
# the hand, are _row_fit()'s: never an overlap.
#
# Called after every draw/discard/play (animate=true, the default -
# existing slots glide to their updated targets over reflow_duration_sec)
# and by every fan/spacing export's own live setter (animate=false -
# snaps immediately, since that's a designer tuning it from the Remote
# tab, not a gameplay event worth animating). A slot with no prior arc
# entry (brand new this call) always snaps to its target rather than
# animating in from Control.new()'s default (0,0) - it wasn't anywhere
# coherent yet to glide from. A lifted slot (hovered/armed) keeps
# updating its own STORED target here so it returns to the right place on
# lower, but neither its live rotation nor z_index are touched while
# lifted - see _on_card_lifted()/_on_card_lowered() for who owns those
# until then.
func _reflow_hand(animate: bool = true, duration: float = -1.0) -> void:
	# The armed slot is laid out as if it weren't there - the fan closes
	# under it; its own position is _on_card_armed()'s.
	# So is a drawn slot still waiting to launch - it joins at its launch.
	var slots: Array[Control] = []
	for slot in _slots:
		if slot != _armed_slot and not _waiting_slots.has(slot):
			slots.append(slot)
	var count: int = slots.size()
	if duration < 0.0:
		duration = reflow_duration_sec
	if count == 0:
		return

	var fit: Vector2 = _row_fit(count)
	var scale_factor: float = fit.x
	var scaled_card_size: Vector2 = card_size * scale_factor

	var spacing_x: float = scaled_card_size.x + fit.y

	var total_width: float = scaled_card_size.x + spacing_x * float(count - 1)
	var start_center_x: float = _row_centre_x() - total_width / 2.0 + scaled_card_size.x / 2.0

	var index := 0
	for slot: Control in slots:
		var t: float = 0.0 if count == 1 else (float(index) / float(count - 1)) * 2.0 - 1.0
		var rotation_degrees: float = t * fan_max_rotation_degrees
		var lift: float = fan_arc_height * (1.0 - t * t)
		var card_center_x: float = start_center_x + spacing_x * float(index)
		# The card is drawn centred card_size.x / 2 into its slot (scaled
		# about its own bottom centre), not at the slot's own centre - so
		# the slot goes where that puts the drawn card on card_center_x.
		var target_position := Vector2(card_center_x - card_size.x / 2.0, -lift)

		slot.custom_minimum_size = scaled_card_size
		# Bottom-center pivot - cards fan out from a shared point below
		# the visible hand, same as a real hand of cards held from below.
		slot.pivot_offset = Vector2(scaled_card_size.x / 2.0, scaled_card_size.y)

		var card_view: CardView = slot.get_child(0) as CardView
		card_view.set_base_scale(scale_factor)

		var is_new_slot: bool = not _arc_positions.has(slot)
		# A glide still running from the last reflow is retargeted, not
		# left to race this one for the same slot.
		_kill_reflow_tween(slot)
		if animate and not is_new_slot:
			var tween := create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_parallel(true)
			tween.tween_property(slot, "position", target_position, duration)
			if not _lifted_slots.has(slot):
				tween.tween_property(slot, "rotation_degrees", rotation_degrees, duration)
			_reflow_tweens[slot] = tween
		else:
			slot.position = target_position
			if not _lifted_slots.has(slot):
				slot.rotation_degrees = rotation_degrees

		_arc_positions[slot] = target_position
		_arc_rotations[slot] = rotation_degrees
		_arc_z_indices[slot] = index
		if not _lifted_slots.has(slot):
			slot.z_index = index

		index += 1

# The row's centre, in this control's own space: midway between the two
# limits (viewport x).
func _row_centre_x() -> float:
	return (hand_left_limit_x + hand_right_limit_x) / 2.0 - global_position.x

# The card scale (x) and edge gap (y) for a row of `count` cards between
# the limits: hand_card_scale at fan_gap while that fits; past it the gap
# closes, down to hand_min_gap_px; past that the cards shrink until the
# row fits. Never an overlap, so every cost numeral shows. The limits
# bound the cards as drawn: the outer cards' tilt reach past their own
# edges (_tilt_overhang(), at hand_card_scale - a smaller card, its top
# lower beside the pivot, reaches less) comes off both sides of the span,
# which keeps the row centred.
func _row_fit(count: int) -> Vector2:
	var overhang: Vector2 = _tilt_overhang(hand_card_scale, count)
	var span: float = hand_right_limit_x - hand_left_limit_x - 2.0 * maxf(overhang.x, overhang.y)
	var width: float = card_size.x * hand_card_scale
	var gaps: float = float(count - 1)
	if float(count) * width + gaps * fan_gap <= span:
		return Vector2(hand_card_scale, fan_gap)
	if count > 1:
		var gap: float = (span - float(count) * width) / gaps
		if gap >= hand_min_gap_px:
			return Vector2(hand_card_scale, gap)
	var card_scale: float = (span - gaps * hand_min_gap_px) / (float(count) * card_size.x)
	return Vector2(clampf(card_scale, 0.05, hand_card_scale), hand_min_gap_px)

# How far a row's outer cards reach past their own drawn edges once
# tilted, left (x) and right (y): the slot turns about its bottom centre,
# so the card's top corner - above that pivot - leans out. The card is
# card_size scaled about its own bottom centre, so its edges sit at
# card_size.x / 2 -+ half its scaled width in the slot. A lone card
# doesn't tilt.
func _tilt_overhang(card_scale: float, count: int) -> Vector2:
	var theta: float = deg_to_rad(fan_max_rotation_degrees) if count > 1 else 0.0
	var pivot := Vector2(card_size.x * card_scale / 2.0, card_size.y * card_scale)
	var top: float = (card_size.y - hand_rest_visible_height) + card_size.y * (1.0 - card_scale)
	var rise: float = maxf(pivot.y - top, 0.0)
	var left_edge: float = card_size.x / 2.0 - card_size.x * card_scale / 2.0
	var right_edge: float = card_size.x / 2.0 + card_size.x * card_scale / 2.0
	var left_x: float = pivot.x + cos(theta) * (left_edge - pivot.x) - sin(theta) * rise
	var right_x: float = pivot.x + cos(theta) * (right_edge - pivot.x) + sin(theta) * rise
	return Vector2(maxf(left_edge - left_x, 0.0), maxf(right_x - right_edge, 0.0))
