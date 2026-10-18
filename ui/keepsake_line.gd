extends InkLine
class_name KeepsakeLine

# One equipment slot of the field HUD, in the column above the row (see
# HudRowStyle's Equipment group for every size): its caps label in the
# row's faint label style ("KEEPSAKE", "WORN", "WEAPON"), under it the piece's art
# (cropped square - the placeholder's tone with no art) framed by four
# hairline corner ticks, no box, and the piece's name beside the frame in
# Spectral at hud_keepsake_size_px, full ink, with the faint hairline
# under it that says it can be hovered. No rarity colour. An empty slot
# still shows: its label, faint ticks and a faint "—", nothing to hover.
#
# Hovering a filled slot shows the keepsake's KeepsakeTile at hud_
# keepsake_tile_scale just above the slot (below, with no room above),
# fading in and out. The hover is polled, never a mouse event; a Control
# under the cursor wins, as on HPBar. A left click on it opens
# KeepsakeExamine (RegionField checks is_point_over() before the click
# can be a move).
#
# RegionField creates it in _setup_field_hud() and sits it on DECK
# (sit_beside()): left-aligned with the row, above it past the hairline
# this slot draws between them; RunState.keepsake_changed keeps it
# current. It goes with the row for a fight, as every row item does.
#
# The WORN slot is this same line with slot WORN, set before it enters the
# tree: RegionField sits it on the KEEPSAKE slot (above it, hud_slot_gap_
# px apart), RunState.worn_changed keeps it current, and its hover is the
# piece's ArmorPlate (at worn_plate_scale) rather than a KeepsakeTile -
# armor's one presentation, as the tile is a keepsake's. Its click opens
# ArmorExamine.
#
# The WEAPON slot is this line again with shows_weapon, set before it
# enters the tree: RegionField sits it on WORN, the column's top;
# RunState.weapon_changed keeps it current (a run always has one). Its
# hover is the weapon's ArmorPlate (set_weapon()), at worn_plate_scale,
# and its click opens the weapon's ArmorExamine.

# Which of the run's slots this line shows. Set before _ready().
var slot: TrinketData.Slot = TrinketData.Slot.KEEPSAKE
# The run's weapon instead of a trinket slot (slot is then unread). Set
# before _ready().
var shows_weapon: bool = false
# The WORN hover's plate scale - the plate is wider than a tile.
@export var worn_plate_scale: float = 0.6:
	set(value):
		worn_plate_scale = value
		_place_tile()

var _keepsake: TrinketData = null
# The WEAPON line's weapon, in place of _keepsake.
var _weapon: WeaponData = null
var _tile: KeepsakeTile = null
# The WORN line's hover, in place of _tile.
var _plate: ArmorPlate = null
# The tile's share of full opacity, 0..1, eased toward the hover.
var _reveal_alpha: float = 0.0

func _ready() -> void:
	if shows_weapon:
		label_text = "WEAPON"
	else:
		label_text = "WORN" if slot == TrinketData.Slot.WORN else "KEEPSAKE"
	super()
	_tile = KeepsakeTile.new()
	_tile.name = "Tile"
	_tile.visible = false
	add_child(_tile)
	if shows_weapon:
		_plate = ArmorPlate.new()
		_plate.name = "Plate"
		_plate.visible = false
		add_child(_plate)
		RunState.weapon_changed.connect(set_weapon)
		set_weapon(RunState.weapon)
	elif slot == TrinketData.Slot.WORN:
		_plate = ArmorPlate.new()
		_plate.name = "Plate"
		_plate.visible = false
		add_child(_plate)
		RunState.worn_changed.connect(set_keepsake)
		set_keepsake(RunState.worn)
	else:
		RunState.keepsake_changed.connect(set_keepsake)
		set_keepsake(RunState.keepsake)

func set_keepsake(keepsake: TrinketData) -> void:
	_keepsake = keepsake
	if _tile != null:
		_tile.set_keepsake(keepsake)
	if _plate != null:
		_plate.set_piece(keepsake)
	set_value_text(keepsake.display_name if keepsake != null else "")

func get_keepsake() -> TrinketData:
	return _keepsake

# The WEAPON line's weapon.
func set_weapon(weapon: WeaponData) -> void:
	_weapon = weapon
	if _plate != null:
		_plate.set_weapon(weapon)
	set_value_text(weapon.display_name if weapon != null else "")

func get_weapon() -> WeaponData:
	return _weapon

# Whether the slot holds anything - a trinket, or the weapon.
func _is_filled() -> bool:
	return _keepsake != null or _weapon != null

# The hover's tile (for probes and the examine view's start).
func get_tile() -> KeepsakeTile:
	return _tile

# The WORN or WEAPON line's hover plate; null on the KEEPSAKE line.
func get_plate() -> ArmorPlate:
	return _plate

# The slot always shows - empty, as faint ticks and a "—".
func _is_shown() -> bool:
	return true

# The KEEPSAKE slot sits on the row (DECK), past the hairline between
# them; WORN sits on KEEPSAKE.
func _sits_on_row() -> bool:
	return not (_beside is KeepsakeLine)

# The room under this slot, above what it sits on.
func _gap_before() -> float:
	if _sits_on_row():
		return style.hud_equipment_rule_gap_px * 2.0 + style.hud_equipment_rule_px
	return style.hud_slot_gap_px

# Above what it sits on, left edges level.
func _position_by(anchor: Control) -> Vector2:
	return Vector2(anchor.position.x, anchor.position.y - _gap_before() - size.y)

func _name_text() -> String:
	return _value_text if _is_filled() else style.hud_slot_empty_text

func _label_baseline() -> float:
	return roundf(style.label_font_tracked().get_ascent(style.hud_label_size_px))

func _frame_rect() -> Rect2:
	var top: float = _label_baseline() + style.hud_slot_label_gap_px
	return Rect2(0.0, top, style.hud_slot_frame_px, style.hud_slot_frame_px)

func _name_left() -> float:
	return style.hud_slot_frame_px + style.hud_slot_name_gap_px

func _content_width() -> float:
	var label_width: float = InkType.width(style.label_font_tracked(), label_text, style.hud_label_size_px)
	var name_width: float = InkType.width(style.hud_keepsake_font, _name_text(), style.hud_keepsake_size_px)
	return maxf(label_width, _name_left() + name_width)

func _content_height() -> float:
	return _frame_rect().end.y

# Whether a screen point is over a filled slot - its label, frame or name.
func is_point_over(screen_point: Vector2) -> bool:
	return _is_filled() and is_visible_in_tree() and get_global_rect().has_point(screen_point)

func _process(delta: float) -> void:
	var target: float = 1.0 if is_visible_in_tree() and _is_hovered() else 0.0
	if is_equal_approx(_reveal_alpha, target):
		return
	var fade: float = style.hud_keepsake_tile_fade_sec
	_reveal_alpha = target if fade <= 0.0 else move_toward(_reveal_alpha, target, delta / fade)
	_place_tile()

func _is_hovered() -> bool:
	if not _is_filled() or get_viewport().gui_get_hovered_control() != null:
		return false
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())

# Above the slot, left-aligned with it; below when it wouldn't fit above.
# The WORN and WEAPON slots' plate the same way.
func _place_tile() -> void:
	if _tile == null or style == null:
		return
	var reveal: Control = _plate if _plate != null else _tile
	reveal.visible = _reveal_alpha > 0.0
	reveal.modulate.a = _reveal_alpha
	if not reveal.visible:
		return
	var reveal_size: Vector2
	if _plate != null:
		if not is_equal_approx(_plate.plate_scale, worn_plate_scale):
			_plate.plate_scale = worn_plate_scale
		reveal_size = _plate.get_plate_size()
	else:
		if not is_equal_approx(_tile.tile_scale, style.hud_keepsake_tile_scale):
			_tile.tile_scale = style.hud_keepsake_tile_scale
		reveal_size = _tile.get_tile_size()
	var above: float = -reveal_size.y - style.hud_keepsake_tile_gap_px
	if get_global_rect().position.y + above < 0.0:
		above = size.y + style.hud_keepsake_tile_gap_px
	reveal.position = Vector2(0.0, roundf(above))

func _draw() -> void:
	var filled: bool = _is_filled()
	var faint := Color(_ink, _ink.a * style.hud_slot_empty_alpha)
	# The label, in the row's caps.
	var label_font: Font = style.label_font_tracked()
	var label_size: int = style.hud_label_size_px
	var label_origin := Vector2(0.0, _label_baseline())
	style.draw_halo_run(self, label_font, label_text, label_origin, label_size)
	InkType.draw_run(self, label_font, label_text, label_origin, label_size, Color(_ink, _ink.a * style.hud_label_alpha))
	# The frame: the art inside four ticks.
	var frame: Rect2 = _frame_rect()
	if filled:
		_draw_art(frame.grow(-style.hud_slot_icon_inset_px))
	HudRowStyle.draw_corner_ticks(self, frame, style.hud_slot_tick_px, style.hud_slot_tick_stroke_px, _ink if filled else faint)
	# The name beside it, its cap height centred on the frame.
	var name_font: Font = style.hud_keepsake_font
	var name_size: int = style.hud_keepsake_size_px
	var text: String = _name_text()
	var baseline: float = roundf(frame.get_center().y + name_font.get_ascent(name_size) * 0.36)
	var left: float = _name_left()
	style.draw_halo_run(self, name_font, text, Vector2(left, baseline), name_size)
	InkType.draw_run(self, name_font, text, Vector2(left, baseline), name_size, _ink if filled else faint)
	if filled:
		var width: float = InkType.width(name_font, text, name_size)
		var hairline_top: float = baseline + style.hud_keepsake_hairline_gap_px
		draw_rect(Rect2(left, hairline_top, width, style.hud_keepsake_hairline_px), Color(_ink, _ink.a * style.hud_keepsake_hairline_alpha))
	# The KEEPSAKE slot draws the hairline between the column and the row.
	if _sits_on_row() and style.hud_equipment_rule_px > 0.0:
		var rule_top: float = size.y + style.hud_equipment_rule_gap_px
		draw_rect(Rect2(0.0, rule_top, style.hud_equipment_rule_length_px, style.hud_equipment_rule_px), Color(_ink, _ink.a * style.hud_equipment_rule_alpha))

# The art, cropped to a centred square - or the placeholder's tone.
func _draw_art(rect: Rect2) -> void:
	var art: Texture2D = _weapon.art if _weapon != null else _keepsake.art
	if art == null:
		draw_rect(rect, style.hud_keepsake_thumb_placeholder)
		return
	var full: Vector2 = art.get_size()
	var crop: float = minf(full.x, full.y)
	draw_texture_rect_region(art, rect, Rect2((full - Vector2(crop, crop)) / 2.0, Vector2(crop, crop)))
