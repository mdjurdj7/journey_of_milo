extends CanvasLayer
class_name ArmorExamine

# A worn piece looked at closely: its ItemPlate at examine_scale (the one
# plate scale, every host's: the hovers', the offers'), centred
# over the dimmed field - KeepsakeExamine, for armor. It grows out of
# from_rect (the HUD row's WORN line; empty: from the middle) while an ink
# scrim fades in, over inspect_duration_sec, and goes back the same way.
#
# Two uses (RegionField opens both, locking the field under it until
# `closed`):
#   the piece on the sand (WorldArmor) - with_choice: TAKE and LEAVE in
#     the strip under the plate, and the "Replaces ..." line when
#     something is worn. TAKE
#     closes with taken = true; LEAVE, a click off the plate, Escape or a
#     right click close with false - the piece stays where it lies.
#   the piece worn (the WORN line) - no choice: any click, Escape or a
#     right click closes.
#   a Bedroll offered (the collector's, setup_bedroll()): its plate with
#     TAKE and LEAVE; LEAVE, a click off, Escape or a right click close
#     it with nothing taken.
#   the run's weapon (the WEAPON line, setup_weapon()) - the same, on its
#     weapon plate (ItemPlate.set_weapon()).
#   a weapon offered (the Greyshelf's - setup_weapon() with_choice): TAKE
#     and LEAVE, and "REPLACES" the weapon carried. Only a choice closes
#     it - a click off the plate, Escape and a right click do nothing,
#     since a weapon left is gone for good (_choice_only) - unless the
#     host passes `escapable` (the collector's: BACK leaves it on sale).
# First loot is revealed (setup()/setup_weapon() with `reveal`): a weapon's
# offer, and a worn piece's first look on the sand - the plate centred at
# reveal_scale, eased in from examine_scale and from clear over
# reveal_duration_sec. Every other look is at examine_scale.
# Layer 100, running ALWAYS.

signal closed(taken: bool)

@export var examine_scale: float = 1.0
@export var inspect_duration_sec: float = 0.15
# A host may set its own (the collector's: its fog) - re-applied live.
@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.35):
	set(value):
		scrim_color = value
		if _scrim != null:
			_scrim.color = value
@export var reveal_scale: float = 1.6
@export var reveal_duration_sec: float = 0.3

var _piece: TrinketData = null
var _weapon: WeaponData = null
var _bedroll: BedrollData = null
# The Warped Shell, and the card in the deck it would change.
var _shell: WarpedShellData = null
var _shell_host: CardData = null
var _worn: TrinketData = null
# The weapon carried, which taking an offered one would replace.
var _carried: WeaponData = null
var _with_choice: bool = false
# A weapon offer: TAKE or LEAVE is the only way out.
var _choice_only: bool = false
# First loot: opens at reveal_scale.
var _reveal: bool = false
var _from_rect: Rect2 = Rect2()
# The run's max HP, for the offer's "Max HP a → b" line (-1: none).
var _max_hp: int = -1
var _scrim: ColorRect = null
var _plate: ItemPlate = null
# The offer inside the plate, no strip (ItemPlate.joined_offer) - set
# before the layer enters the tree (the collector's).
var joined_offer: bool = false
var _tween: Tween = null
var _closing: bool = false

# Called before the layer enters the tree. `worn`: the piece worn now,
# which taking this would replace (with_choice only); `max_hp`: the run's
# max HP, so the offer says what taking it makes that (ItemPlate.set_max_
# hp()), -1 for no line.
func setup(piece: TrinketData, worn: TrinketData, with_choice: bool, from_rect: Rect2 = Rect2(), reveal: bool = false, max_hp: int = -1) -> void:
	_piece = piece
	_worn = worn
	_with_choice = with_choice
	_from_rect = from_rect
	_reveal = reveal
	_max_hp = max_hp

# The weapon instead of a piece - no choice, or for an offer with_choice
# and `carried`, the weapon taking it would replace. Called before the
# layer enters the tree.
func setup_weapon(weapon: WeaponData, from_rect: Rect2 = Rect2(), carried: WeaponData = null, with_choice: bool = false, reveal: bool = false, escapable: bool = false) -> void:
	setup(null, null, with_choice, from_rect, reveal)
	_weapon = weapon
	_carried = carried
	_choice_only = with_choice and not escapable

# The Bedroll instead of a piece, offered with_choice or only shown.
# Called before the layer enters the tree.
func setup_bedroll(bedroll: BedrollData, with_choice: bool = false, from_rect: Rect2 = Rect2()) -> void:
	setup(null, null, with_choice, from_rect)
	_bedroll = bedroll

# The Warped Shell instead of a piece: `host` becoming what the shell makes
# it, offered with_choice. Called before the layer enters the tree.
func setup_shell(shell: WarpedShellData, host: CardData, with_choice: bool = true, reveal: bool = false) -> void:
	setup(null, null, with_choice, Rect2(), reveal)
	_shell = shell
	_shell_host = host

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click must not reach the field.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_gui_input)
	_scrim.modulate.a = 0.0
	add_child(_scrim)
	_plate = ItemPlate.new()
	_plate.name = "Plate"
	# Looked at closely: the cards it names show on hover (the Tail's Lash).
	_plate.card_links_enabled = true
	_plate.joined_offer = joined_offer
	add_child(_plate)
	if _piece == null and _weapon == null and _bedroll == null and _shell == null:
		close(false)
		return
	if _shell != null:
		_plate.set_shell(_shell, _shell_host, _with_choice)
	elif _bedroll != null:
		_plate.set_bedroll(_bedroll, _with_choice)
	elif _weapon != null:
		_plate.set_weapon(_weapon, _carried if _with_choice else null, _with_choice)
	else:
		_plate.set_piece(_piece, _worn if _with_choice else null, _with_choice)
		if _with_choice:
			_plate.set_max_hp(_max_hp)
	_plate.chosen.connect(close)
	# With no choice, a click on the plate closes as one off it does - the
	# plate only watches the mouse for its card names (PASS).
	if not _with_choice:
		_plate.gui_input.connect(_on_scrim_gui_input)
	_open()
	_plate.play_name_sheen()

func get_plate() -> ItemPlate:
	return _plate

# Grows from from_rect (at the scale that fits it) to the centre - or,
# first loot, from examine_scale and clear to reveal_scale, centred
# throughout (its position and size ease alike).
func _open() -> void:
	var view: Vector2 = _scrim.get_viewport_rect().size
	var unit: Vector2 = _plate.get_plate_size() / _plate.plate_scale
	if _reveal:
		_plate.plate_scale = examine_scale
		_plate.position = ((view - unit * examine_scale) / 2.0).round()
		_plate.modulate.a = 0.0
		var tween: Tween = _tween_to(reveal_scale, ((view - unit * reveal_scale) / 2.0).round(), 1.0, reveal_duration_sec)
		tween.tween_property(_plate, "modulate:a", 1.0, reveal_duration_sec)
		return
	var start_scale: float = examine_scale
	var start_position: Vector2
	if _from_rect.size.x > 0.0:
		start_scale = clampf(_from_rect.size.y / maxf(unit.y, 1.0), 0.1, examine_scale)
		start_position = _from_rect.position
	else:
		start_position = (view - unit * start_scale) / 2.0
	_plate.plate_scale = start_scale
	_plate.position = start_position
	_tween_to(examine_scale, ((view - unit * examine_scale) / 2.0).round(), 1.0)

func _tween_to(to_scale: float, to_position: Vector2, scrim_alpha: float, duration: float = -1.0) -> Tween:
	if duration < 0.0:
		duration = inspect_duration_sec
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)
	_tween.tween_property(_plate, "plate_scale", to_scale, duration)
	_tween.tween_property(_plate, "position", to_position, duration)
	_tween.tween_property(_scrim, "modulate:a", scrim_alpha, duration)
	return _tween

# For probes: whether this look is first loot's reveal.
func is_reveal() -> bool:
	return _reveal

func _on_scrim_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and (button.button_index == MOUSE_BUTTON_LEFT or button.button_index == MOUSE_BUTTON_RIGHT):
		# Taken either way, so it never reaches the field.
		_scrim.accept_event()
		if not _choice_only:
			close(false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if not _choice_only:
			close(false)
		return
	if not _with_choice or _plate == null:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_plate.set_focus(ItemPlate.Choice.LEAVE if _plate.get_focus() == ItemPlate.Choice.TAKE else ItemPlate.Choice.TAKE)
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_plate.activate(_plate.get_focus())

# Back to where it came from (a choice made fades where it stands), then
# gone - and `closed` for the field. The first close wins.
func close(taken: bool) -> void:
	if _closing:
		return
	_closing = true
	if _plate == null or not _plate.has_item():
		closed.emit(false)
		queue_free()
		return
	var unit: Vector2 = _plate.get_plate_size() / _plate.plate_scale
	var back_scale: float = _plate.plate_scale
	var back_position: Vector2 = _plate.position
	if _from_rect.size.x > 0.0:
		back_scale = clampf(_from_rect.size.y / maxf(unit.y, 1.0), 0.1, examine_scale)
		back_position = _from_rect.position
	var tween: Tween = _tween_to(back_scale, back_position, 0.0)
	tween.tween_property(_plate, "modulate:a", 0.0, inspect_duration_sec)
	tween.chain().tween_callback(func() -> void:
		closed.emit(taken)
		queue_free())
