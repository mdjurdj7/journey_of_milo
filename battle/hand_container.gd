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

# Must match CardView.card_size (200 x 280 at 1x).
@export var card_size: Vector2 = Vector2(200.0, 280.0)
# Base display scale for every card in the hand - applied before (and
# composed with) the further shrink-to-fit factor _compute_scale_factor()
# derives against hand_max_span, same "smaller than full card_size for
# this context" role DeckView's own deck_view_card_scale plays there.
@export_range(0.1, 1.0) var hand_card_scale: float = 0.95:
	set(value):
		hand_card_scale = value
		_reflow_hand(false)
@export var draw_stagger_sec: float = 0.07
@export var discard_collapse_duration_sec: float = 0.16
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
		for slot: Control in _views.values():
			var card_view: CardView = slot.get_child(0) as CardView
			card_view.set_rest_offset(card_size.y - hand_rest_visible_height)

# Row width cap, measured against hand_card_scale-sized cards (not full
# card_size) - past this, the hand is scaled down further still (see
# _compute_scale_factor()) so it never runs off-screen regardless of how
# many cards it holds.
@export var hand_max_span: float = 1600.0:
	set(value):
		hand_max_span = value
		_reflow_hand(false)

@export_group("Fan")
# Gap between adjacent cards' edges while the hand holds fan_gap_max_cards
# or fewer - see fan_overlap below for what replaces this once there are
# more.
@export var fan_gap: float = 12.0:
	set(value):
		fan_gap = value
		_reflow_hand(false)
# Above this many cards, adjacent cards switch from fan_gap's fixed edge
# gap to fan_overlap's proportional overlap instead (see _reflow_hand()'s
# own spacing_x branch) - at or below it, cards never overlap regardless
# of fan_overlap's own value.
@export var fan_gap_max_cards: int = 6:
	set(value):
		fan_gap_max_cards = value
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
# Fraction of (scaled) card width adjacent cards overlap by once the hand
# holds more than fan_gap_max_cards cards - below that, cards use
# fan_gap's normal edge gap instead and never overlap at all. Applies
# uniformly to every gap in the hand, not just where it'd otherwise
# overflow hand_max_span.
@export_range(0.0, 0.9) var fan_overlap: float = 0.15:
	set(value):
		fan_overlap = value
		_reflow_hand(false)

@export_group("Play Tween")
@export var play_to_target_duration_sec: float = 0.25
@export var play_to_discard_duration_sec: float = 0.2
@export var discard_point: Vector2 = Vector2(1750.0, 150.0)

var _deck: Deck = null
var _views: Dictionary = {} # CardData -> Control (the card's slot; its only child is a CardView)
# The player's current energy, as last pushed by update_playable() - a
# card drawn later is faded or not against this same number.
var _last_energy: int = -1
var _pending_reveals: Array[CardData] = []
var _revealing: bool = false

# No longer a Container (HBoxContainer defaulted this to IGNORE on its
# own) - the arc leaves real gaps between/around fanned cards where the
# battle scene behind should stay clickable, same reasoning BattleOverlay
# itself already sets this for.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

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

func set_deck(deck: Deck) -> void:
	if _deck != null:
		_deck.drawn.disconnect(_on_card_drawn)
		_deck.discarded.disconnect(_on_card_discarded)
	_deck = deck
	_deck.drawn.connect(_on_card_drawn)
	_deck.discarded.connect(_on_card_discarded)

func draw_cards(amount: int) -> void:
	if _deck == null:
		return
	_deck.draw(amount)

func discard_hand() -> void:
	if _deck == null:
		return
	_deck.discard_hand()

func _on_card_drawn(card: CardData) -> void:
	_pending_reveals.append(card)
	if not _revealing:
		_reveal_pending_cards()

# Reveals queued cards one at a time, draw_stagger_sec apart - matches the
# old project's per-card deal stagger (see reference/old_project's
# _draw_cards()/_await_deal_stagger()).
func _reveal_pending_cards() -> void:
	_revealing = true
	while not _pending_reveals.is_empty():
		var card: CardData = _pending_reveals.pop_front()
		_add_card_view(card)
		if not _pending_reveals.is_empty():
			await get_tree().create_timer(draw_stagger_sec).timeout
	_revealing = false

# No-op if play_card() already erased this card's entry and freed its view -
# the controller only calls Deck.discard() after play_card()'s own
# choreography (and view removal) has already finished.
func _on_card_discarded(card: CardData) -> void:
	var slot: Control = _views.get(card)
	if slot == null:
		return
	_views.erase(card)
	_forget_slot(slot)
	_reflow_hand()
	_collapse_and_remove(slot)

func _add_card_view(card: CardData) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = card_size

	var card_view := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	card_view.card_size = card_size
	slot.add_child(card_view)

	# Brings slot (and card_view within it) into the live tree, firing
	# CardView._ready() - must happen before set_card_data() below, which
	# needs card_view's @onready label references already populated.
	add_child(slot)

	card_view.set_rest_offset(card_size.y - hand_rest_visible_height)
	card_view.set_card_data(card)
	if _last_energy >= 0:
		card_view.set_playable(card.cost <= _last_energy)
	card_view.clicked.connect(_on_card_view_clicked.bind(card_view))
	card_view.lifted.connect(_on_card_lifted.bind(slot, card_view))
	card_view.lowered.connect(_on_card_lowered.bind(slot, card_view))
	card_view.armed.connect(_on_card_armed.bind(slot, card_view))
	card_view.disarmed.connect(_on_card_disarmed.bind(slot, card_view))
	if _armed_slot != null:
		card_view.set_hover_suppressed(true)

	_views[card] = slot
	_reflow_hand()

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
func update_playable(energy: int) -> void:
	_last_energy = energy
	for card in _views:
		var slot: Control = _views[card]
		var card_view: CardView = slot.get_child(0) as CardView
		if card_view != null:
			card_view.set_playable((card as CardData).cost <= energy)

# Straightens this slot to 0 rotation and brings it to the front of the
# fan - fired for both a plain hover and an armed card (CardView.lifted
# covers both, see its own doc), so a card picked out of the hand either
# way reads the same: level and on top of its neighbors.
func _on_card_lifted(slot: Control, card_view: CardView) -> void:
	_lifted_slots[slot] = true
	slot.z_index = HOVER_Z_INDEX
	var tween := create_tween()
	tween.tween_property(slot, "rotation_degrees", 0.0, card_view.hover_duration_sec)

func _on_card_lowered(slot: Control, card_view: CardView) -> void:
	_lifted_slots.erase(slot)
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
	_armed_slot = slot
	armed_changed.emit(true)
	_lifted_slots.erase(slot)
	for other in _views.values():
		var other_view: CardView = (other as Control).get_child(0) as CardView
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
	for other in _views.values():
		var other_view: CardView = (other as Control).get_child(0) as CardView
		if other_view != null:
			other_view.set_hover_suppressed(false)
	if not _views.values().has(slot):
		return
	slot.z_index = int(_arc_z_indices.get(slot, 0))
	_reflow_hand(true, card_view.armed_duration_sec)

func _forget_slot(slot: Control) -> void:
	_arc_positions.erase(slot)
	_arc_rotations.erase(slot)
	_arc_z_indices.erase(slot)
	_lifted_slots.erase(slot)

func _collapse_and_remove(slot: Control) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(slot, "scale", Vector2.ZERO, discard_collapse_duration_sec)
	tween.tween_callback(slot.queue_free)

# Runs the hand -> target -> discard travel for a played card, removing its
# view when done and emitting play_animation_finished. target_screen_pos is
# wherever the controller decided to aim it (an enemy's unprojected head for
# an ENEMY-target card, or some up-and-away point for SELF/NONE) - this
# function doesn't interpret target_type at all, only where it's told to go.
func play_card(card_data: CardData, target_screen_pos: Vector2) -> void:
	var slot: Control = _views.get(card_data)
	if slot == null:
		return
	_views.erase(card_data)
	_forget_slot(slot)
	_reflow_hand()

	var card_view: CardView = slot.get_child(0) as CardView
	card_view.mark_played()
	if _armed_slot == slot:
		_armed_slot = null
		armed_changed.emit(false)
		for other in _views.values():
			var other_view: CardView = (other as Control).get_child(0) as CardView
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

	var tween := create_tween()
	tween.tween_property(slot, "global_position", target_screen_pos - slot.size / 2.0, play_to_target_duration_sec)
	tween.tween_property(slot, "global_position", discard_point - slot.size / 2.0, play_to_discard_duration_sec)
	tween.parallel().tween_property(card_view, "modulate:a", 0.0, play_to_discard_duration_sec)
	tween.tween_callback(func() -> void:
		slot.queue_free()
		play_animation_finished.emit(card_data)
	)

# Lays every current card out on an arc centered on this container's own
# midpoint: each card's normalized position t (-1 at the leftmost card, 0
# at the hand's center, +1 at the rightmost) drives both its rotation
# (t * fan_max_rotation_degrees) and its vertical lift (a parabola peaking
# at fan_arc_height when t=0, 0 at the two ends) - see the per-card loop
# below. Horizontal spacing is fan_overlap of a card's own width once the
# hand holds more than fan_gap_max_cards cards, fan_gap's normal edge-to-
# edge gap otherwise (see those exports' own doc). scale_factor (hand_card_
# scale, further reduced only if that would still exceed hand_max_span)
# is uniform across the hand regardless of which spacing rule is active.
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
	var slots: Array = []
	for slot: Control in _views.values():
		if slot != _armed_slot:
			slots.append(slot)
	var count: int = slots.size()
	if count == 0:
		return
	if duration < 0.0:
		duration = reflow_duration_sec

	var scale_factor: float = _compute_scale_factor(count)
	var scaled_card_size: Vector2 = card_size * scale_factor

	var spacing_x: float
	if count > fan_gap_max_cards:
		spacing_x = scaled_card_size.x * (1.0 - fan_overlap)
	else:
		spacing_x = scaled_card_size.x + fan_gap

	var total_width: float = scaled_card_size.x + spacing_x * float(count - 1)
	var start_center_x: float = size.x / 2.0 - total_width / 2.0 + scaled_card_size.x / 2.0

	var index := 0
	for slot: Control in slots:
		var t: float = 0.0 if count == 1 else (float(index) / float(count - 1)) * 2.0 - 1.0
		var rotation_degrees: float = t * fan_max_rotation_degrees
		var lift: float = fan_arc_height * (1.0 - t * t)
		var card_center_x: float = start_center_x + spacing_x * float(index)
		var target_position := Vector2(card_center_x - scaled_card_size.x / 2.0, -lift)

		slot.custom_minimum_size = scaled_card_size
		# Bottom-center pivot - cards fan out from a shared point below
		# the visible hand, same as a real hand of cards held from below.
		slot.pivot_offset = Vector2(scaled_card_size.x / 2.0, scaled_card_size.y)

		var card_view: CardView = slot.get_child(0) as CardView
		card_view.set_base_scale(scale_factor)

		var is_new_slot: bool = not _arc_positions.has(slot)
		if animate and not is_new_slot:
			var tween := create_tween()
			tween.set_ease(Tween.EASE_OUT)
			tween.set_trans(Tween.TRANS_CUBIC)
			tween.set_parallel(true)
			tween.tween_property(slot, "position", target_position, duration)
			if not _lifted_slots.has(slot):
				tween.tween_property(slot, "rotation_degrees", rotation_degrees, duration)
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

# hand_card_scale is the base factor (a card in hand is never full
# card_size, regardless of count); this only shrinks further, on top of
# that, once even hand_card_scale-sized cards at fan_gap spacing would
# exceed hand_max_span. natural_width uses fan_gap regardless of the
# overlap rule above (an approximation, not an exact fit, same as before
# this feature existed - see fan_overlap's own doc for the actual overlap
# math this doesn't need to mirror precisely).
func _compute_scale_factor(count: int) -> float:
	var base_card_width: float = card_size.x * hand_card_scale
	var natural_width: float = count * base_card_width + max(count - 1, 0) * fan_gap
	if natural_width > hand_max_span:
		return hand_card_scale * (hand_max_span / natural_width)
	return hand_card_scale
