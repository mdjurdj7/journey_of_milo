extends CanvasLayer
class_name RewardScreen

# What the fight left. Shown once the battle framing has blended back to
# the follow camera, over the live field dimmed behind it - an interim
# screen standing in for the world-placed RewardSpread, which is kept and
# still selectable (see RegionField.reward_mode).
#
# Two states in one column, swapped in place rather than stacked as two
# screens: the LIST of what's on offer, and the card CHOICE. Taking a
# line strikes it through; the screen closes itself when every line is
# taken, or when WALK ON is pressed, whichever comes first. Skipping is
# final - NONE OF THESE strikes the card line exactly as taking it does,
# because the offer is spent either way.
#
# Everything here is bone on the dimmed field: the world is the dark
# element now, so this reads with the theme's ON-DARK values rather than
# the ink the field HUD uses. That inversion is why the colours are this
# node's own exports rather than theme lookups - the theme's value set
# follows the WORLD's lightness (see BattleTheme.apply_value_set()), and
# this screen is over a scrim, not over the world.

signal closed()

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"

@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.40)
# Bone - the on-dark ink of the theme's own pair.
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0)
# Every bone run is drawn over a 1px outline in this, the same
# legibility treatment FloatingNumber and BattleIntent use for text
# sitting directly over the world - the scrim alone doesn't save bone
# text where the sand under it is nearly bone itself. Those two do it
# with Label theme overrides; this screen draws its text, so it draws
# the outline too (see _text()).
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0)
@export var text_outline_px: int = 1

@export_group("Column")
@export var column_width: float = 300.0
@export var header_text: String = "LEFT BEHIND"
@export var header_size_px: int = 11
@export_range(0.0, 1.0) var header_tracking_em: float = 0.22
@export var header_gap_px: float = 28.0
# Each line: Spectral item text on the left, a tracked caps action on the
# right, a hairline under both.
@export var line_height_px: float = 44.0
@export var item_size_px: int = 26
@export var action_size_px: int = 11
@export_range(0.0, 1.0) var action_tracking_em: float = 0.18
@export var rule_px: float = 1.0
@export var rule_hover_px: float = 2.0
@export_range(0.0, 1.0) var rule_alpha: float = 0.45
@export var strike_px: float = 1.0
@export_range(0.0, 1.0) var taken_alpha: float = 0.45
@export var dismiss_text: String = "WALK ON"
@export var dismiss_size_px: int = 12
@export_range(0.0, 1.0) var dismiss_tracking_em: float = 0.18
@export_range(0.0, 1.0) var dismiss_alpha: float = 0.6
@export var dismiss_gap_px: float = 72.0
@export_group("")

@export_group("Card Choice")
# The cards: a level row, no container, positioned outright under the
# Column control (see _open_choice()) - equal size, no rotation, centred
# on the viewport's width with the row's centre line at choice_row_
# centre_fraction of its height. TAKE ONE sits above the row (baseline
# choice_header_gap_px above the cards' top edge), NONE OF THESE below
# it (choice_dismiss_gap_px of clear space under the cards' bottom
# edge), both centred on the row.
@export var choice_header_text: String = "TAKE ONE"
@export var choice_count: int = 3
@export var card_gap_px: float = 26.0
@export_range(0.0, 1.0) var choice_row_centre_fraction: float = 0.46
@export var choice_header_gap_px: float = 28.0
@export var choice_dismiss_gap_px: float = 40.0
@export var choice_dismiss_text: String = "NONE OF THESE"
@export var card_flight_duration_sec: float = 0.45
# The card being taken (see _play_take_sound()) - once, on the choice
# itself, never on hover, the gold line or a skip. A -6 dBFS take at -18
# sits just under the battle's card-play cue (-16).
@export var take_volume_db: float = -18.0
@export var card_flight_end_scale: float = 0.12
@export_group("")

enum Mode { LIST, CHOICE }

# One offer. `taken` covers skipped too: an offer that has been answered,
# however it was answered, is struck and cannot be answered again.
class RewardLine:
	var id: String
	var item: String
	var action: String
	var taken: bool = false
	var rect: Rect2 = Rect2()

var _lines: Array[RewardLine] = []
var _gold: int = 0
var _pool: RewardPool = null
var _deck_panel: Control = null
var _mode: int = Mode.LIST
var _hovered: int = -1
var _card_views: Array[CardView] = []
var _taking_card: bool = false
# The card row's rect in Column pixels while a choice is open - what the
# choice header, its dismiss and the dismiss hit-test hang off.
var _choice_row: Rect2 = Rect2()

var _draw_layer: Control = null
var _scrim: ColorRect = null
var _item_font: Font = null
var _header_font: Font = null
var _action_font: Font = null
var _dismiss_font: Font = null

# gold is what this fight rolled; pool is the floor's own, already
# chosen; deck_panel is where a taken card flies to. Called by
# RegionField before the screen is added to the tree.
func setup(gold: int, pool: RewardPool, deck_panel: Control) -> void:
	_gold = gold
	_pool = pool
	_deck_panel = deck_panel

func _ready() -> void:
	# The field is frozen under this (RegionField goes back to
	# PROCESS_MODE_DISABLED while the screen is up), which is also what
	# stops click-to-move and WASD - both live on frozen nodes. This layer
	# has to opt out of that freeze or it would stop with them.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_item_font = InkType.numeral_font()
	_header_font = InkType.tracked(InkType.text_bold_font(), header_size_px, header_tracking_em)
	_action_font = InkType.tracked(InkType.text_bold_font(), action_size_px, action_tracking_em)
	_dismiss_font = InkType.tracked(InkType.text_bold_font(), dismiss_size_px, dismiss_tracking_em)

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the scrim is what keeps a click from reaching the
	# field underneath and ordering the Wanderer somewhere.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_draw_layer = Control.new()
	_draw_layer.name = "Column"
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_layer.gui_input.connect(_on_gui_input)
	_draw_layer.draw.connect(_draw_column)
	add_child(_draw_layer)

	_build_lines()

func _build_lines() -> void:
	_lines.clear()
	if _gold > 0:
		var gold_line := RewardLine.new()
		gold_line.id = "gold"
		gold_line.item = "%d gold" % _gold
		gold_line.action = "TAKE"
		_lines.append(gold_line)
	if _pool != null and not _pool.entries.is_empty():
		var card_line := RewardLine.new()
		card_line.id = "card"
		card_line.item = "A card"
		card_line.action = "CHOOSE"
		_lines.append(card_line)
	if _lines.is_empty():
		close()

# --- Layout ---

func _column_left() -> float:
	return (_draw_layer.size.x - column_width) / 2.0

func _column_top() -> float:
	var lines_height: float = float(_lines.size()) * line_height_px
	var total: float = float(header_size_px) + header_gap_px + lines_height + dismiss_gap_px + float(dismiss_size_px)
	return (_draw_layer.size.y - total) / 2.0

# The dismiss line's hit rect - under the list, or under the card row
# while a choice is open; _draw_dismiss() draws the text at its
# baseline (top + dismiss_size_px) in either case.
func _dismiss_rect() -> Rect2:
	if _mode == Mode.CHOICE:
		var baseline: float = _choice_row.end.y + choice_dismiss_gap_px + float(dismiss_size_px)
		return Rect2(_choice_row.position.x, baseline - float(dismiss_size_px), _choice_row.size.x, float(dismiss_size_px) * 2.0)
	var top: float = _column_top() + float(header_size_px) + header_gap_px + float(_lines.size()) * line_height_px + dismiss_gap_px
	return Rect2(_column_left(), top - float(dismiss_size_px), column_width, float(dismiss_size_px) * 2.0)

# --- Draw ---

# One bone run with its ink outline under it. The outline carries the
# text's own alpha, so a struck-through line fades as one thing rather
# than leaving a hard outline around faded letters. Returns the advance
# width, like InkType.draw_run(), so callers can still run text along a
# baseline.
func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> float:
	if font == null or text.is_empty():
		return 0.0
	if text_outline_px > 0:
		var outline: Color = ink
		outline.a = ink.a * color.a
		_draw_layer.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	return InkType.draw_run(_draw_layer, font, text, origin, size_px, color)

func _draw_column() -> void:
	if _mode == Mode.CHOICE:
		_draw_choice()
		return
	var left: float = _column_left()
	var top: float = _column_top()
	var baseline: float = top + float(header_size_px)
	_text(_header_font, header_text, Vector2(left, baseline), header_size_px, bone)

	var y: float = top + float(header_size_px) + header_gap_px
	for index in _lines.size():
		var line: RewardLine = _lines[index]
		line.rect = Rect2(left, y, column_width, line_height_px)
		var text_baseline: float = y + line_height_px * 0.62
		var color: Color = bone
		if line.taken:
			color.a = taken_alpha
		_text(_item_font, line.item, Vector2(left, text_baseline), item_size_px, color)
		var action_width: float = InkType.width(_action_font, line.action, action_size_px)
		_text(_action_font, line.action, Vector2(left + column_width - action_width, text_baseline), action_size_px, color)

		var rule_color: Color = bone
		rule_color.a = rule_alpha * (taken_alpha if line.taken else 1.0)
		var thickness: float = rule_hover_px if (_hovered == index and not line.taken) else rule_px
		_draw_layer.draw_rect(Rect2(left, y + line_height_px - thickness, column_width, thickness), rule_color)

		if line.taken:
			# Struck through the text itself, not the rule - the offer is
			# crossed off, the line it sat on is still there.
			var strike_y: float = text_baseline - float(item_size_px) * 0.3
			_draw_layer.draw_rect(Rect2(left, strike_y, column_width, strike_px), color)
		y += line_height_px

	_draw_dismiss(dismiss_text)

func _draw_dismiss(text: String) -> void:
	var color: Color = bone
	color.a = dismiss_alpha
	var width: float = InkType.width(_dismiss_font, text, dismiss_size_px)
	var rect: Rect2 = _dismiss_rect()
	_text(_dismiss_font, text, Vector2(rect.position.x + (rect.size.x - width) / 2.0, rect.position.y + float(dismiss_size_px)), dismiss_size_px, color)

func _draw_choice() -> void:
	var width: float = InkType.width(_header_font, choice_header_text, header_size_px)
	var baseline: float = _choice_row.position.y - choice_header_gap_px
	_text(_header_font, choice_header_text, Vector2(_choice_row.position.x + (_choice_row.size.x - width) / 2.0, baseline), header_size_px, bone)
	_draw_dismiss(choice_dismiss_text)

# --- Input ---

func _on_gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var was: int = _hovered
		_hovered = _line_at(motion.position) if _mode == Mode.LIST else -1
		if was != _hovered:
			_draw_layer.queue_redraw()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	if _dismiss_rect().has_point(button.position):
		_on_dismiss()
		_draw_layer.accept_event()
		return
	if _mode != Mode.LIST:
		return
	var index: int = _line_at(button.position)
	if index >= 0:
		_take_line(index)
		_draw_layer.accept_event()

func _line_at(position: Vector2) -> int:
	for index in _lines.size():
		if _lines[index].rect.has_point(position) and not _lines[index].taken:
			return index
	return -1

func _on_dismiss() -> void:
	if _mode == Mode.CHOICE:
		# Skipping is final: the offer is spent whether or not a card was
		# taken, so the line is struck exactly as taking would.
		_finish_card_line()
		return
	close()

func _take_line(index: int) -> void:
	var line: RewardLine = _lines[index]
	if line.taken:
		return
	match line.id:
		"gold":
			RunState.add_gold(_gold)
			print("RewardScreen: took %d gold (run total %d)." % [_gold, RunState.gold])
			line.taken = true
			_hovered = -1
			_draw_layer.queue_redraw()
			_close_if_spent()
		"card":
			_open_choice()

# --- Card choice ---

func _open_choice() -> void:
	var rolled: Array[CardData] = _pool.roll(choice_count, RunState.rng)
	if rolled.is_empty():
		_finish_card_line()
		return
	_mode = Mode.CHOICE
	_hovered = -1
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("RewardScreen: could not load %s; skipping the choice." % CARD_VIEW_SCENE_PATH)
		_finish_card_line()
		return
	var reference := scene.instantiate() as CardView
	var card_size: Vector2 = reference.card_size
	reference.free()

	# Whole pixels, so the card faces don't land on half-pixel edges.
	var span: float = float(rolled.size()) * card_size.x + float(rolled.size() - 1) * card_gap_px
	var start_x: float = roundf((_draw_layer.size.x - span) / 2.0)
	var top: float = roundf(_draw_layer.size.y * choice_row_centre_fraction - card_size.y * 0.5)
	_choice_row = Rect2(start_x, top, span, card_size.y)
	for index in rolled.size():
		var card_view := scene.instantiate() as CardView
		# Hover grows the card in place, about its own centre, and moves
		# nothing: no lift (a hand card's hover_lift is a position.y tween
		# measured from its rest offset - here rest IS the row), and the
		# pivot set AFTER add_child(), since CardView._ready() puts a
		# hover-enabled card's pivot at its bottom centre for the hand.
		card_view.hover_lift = 0.0
		card_view.position = Vector2(start_x + float(index) * (card_size.x + card_gap_px), top)
		_draw_layer.add_child(card_view)
		card_view.set_rest_offset(top)
		card_view.pivot_offset = card_size / 2.0
		card_view.set_card_data(rolled[index])
		card_view.clicked.connect(_on_choice_clicked.bind(card_view))
		_card_views.append(card_view)
	_draw_layer.queue_redraw()

func _on_choice_clicked(card_data: CardData, card_view: CardView) -> void:
	if _taking_card:
		return
	_taking_card = true
	RunState.add_card(card_data)
	_play_take_sound()
	print("RewardScreen: took '%s' (deck now %d)." % [card_data.card_name, RunState.deck.size()])
	for other in _card_views:
		if other != card_view and is_instance_valid(other):
			other.queue_free()
	_fly_to_deck(card_view)

# The take's sound, on its own 2D player on the SFX bus - parented to the
# tree's ROOT with process ALWAYS and freed on its own `finished`, so it
# plays to the end whatever happens to this node next: this screen
# closes and frees itself once its lines are spent, right after the
# card's flight, and RegionField (its parent) stands DISABLED for as
# long as it is open. load() at the moment of taking, never a preloaded
# stream. The twin of this lives on WorldCard - two consumers, not yet a
# helper.
func _play_take_sound() -> void:
	var stream := load(TAKE_SFX_PATH) as AudioStream
	if stream == null:
		push_warning("RewardScreen: card-take SFX failed to load (%s); silent." % TAKE_SFX_PATH)
		return
	var player := AudioStreamPlayer.new()
	player.name = "CardTakeAudio"
	player.bus = &"SFX"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.volume_db = take_volume_db
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()

# Lifted from WorldCard._fly_to_deck() rather than shared: two consumers
# is not yet three, and the two differ in what they fly (a Control this
# node owns, vs one a 3D anchor owns) and in what happens after.
func _fly_to_deck(card_view: CardView) -> void:
	card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var destination: Vector2 = _deck_panel_centre()
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(card_view, "position", destination - card_view.card_size * card_flight_end_scale / 2.0, card_flight_duration_sec)
	tween.tween_property(card_view, "scale", Vector2.ONE * card_flight_end_scale, card_flight_duration_sec)
	tween.tween_property(card_view, "modulate:a", 0.0, card_flight_duration_sec)
	tween.chain().tween_callback(func() -> void:
		if is_instance_valid(card_view):
			card_view.queue_free()
		_finish_card_line())

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		push_warning("RewardScreen: no DeckPanel to fly to; dropping the card off-screen instead.")
		return Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

# Back to the list with the card line struck - the same ending whether a
# card was taken or the choice was declined.
func _finish_card_line() -> void:
	for view in _card_views:
		if is_instance_valid(view):
			view.queue_free()
	_card_views.clear()
	_taking_card = false
	_mode = Mode.LIST
	for line in _lines:
		if line.id == "card":
			line.taken = true
	_draw_layer.queue_redraw()
	_close_if_spent()

func _close_if_spent() -> void:
	for line in _lines:
		if not line.taken:
			return
	close()

func close() -> void:
	closed.emit()
	queue_free()
