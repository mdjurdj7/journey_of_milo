extends InkLine
class_name KeepsakeLine

# The field HUD row's keepsake: a small square of its art (cropped square,
# a thin ink edge - the placeholder's tone with no art), then its name in
# Spectral at hud_keepsake_size_px, full ink (the row's halo under it,
# when it has one), with a faint ink hairline under the name that says it
# can be hovered - set apart at the end of the row by hud_keepsake_gap_px,
# after GOLD and GLASSBONE (see InkLine for the following, HudRowStyle for
# every size). No label, no rarity colour. Hidden while the slot is
# empty.
#
# Hovering it shows the keepsake's KeepsakeTile at hud_keepsake_tile_
# scale just above the row (below, with no room above), fading in and
# out. The hover is polled, never a mouse event; a Control under the
# cursor wins, as on HPBar. A left click on it opens KeepsakeExamine
# (RegionField checks is_point_over() before the click can be a move).
#
# RegionField creates it in _setup_field_hud() and hands it the
# GLASSBONE line (sit_beside() - beside GOLD while GLASSBONE is hidden);
# RunState.keepsake_changed keeps it current.

var _keepsake: TrinketData = null
var _tile: KeepsakeTile = null
# The tile's share of full opacity, 0..1, eased toward the hover.
var _reveal_alpha: float = 0.0

func _ready() -> void:
	super()
	_tile = KeepsakeTile.new()
	_tile.name = "Tile"
	_tile.visible = false
	add_child(_tile)
	RunState.keepsake_changed.connect(set_keepsake)
	set_keepsake(RunState.keepsake)

func set_keepsake(keepsake: TrinketData) -> void:
	_keepsake = keepsake
	if _tile != null:
		_tile.set_keepsake(keepsake)
	set_value_text(keepsake.display_name if keepsake != null else "")

func get_keepsake() -> TrinketData:
	return _keepsake

# The hover's tile (for probes and the examine view's start).
func get_tile() -> KeepsakeTile:
	return _tile

func _is_shown() -> bool:
	return _keepsake != null

func _gap_before() -> float:
	return style.hud_keepsake_gap_px

func _thumb_width() -> float:
	return style.hud_keepsake_thumb_px + style.hud_keepsake_thumb_gap_px

func _content_width() -> float:
	return _thumb_width() + InkType.width(style.hud_keepsake_font, _value_text, style.hud_keepsake_size_px)

# Whether a screen point is over the thumbnail or the name.
func is_point_over(screen_point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(screen_point)

func _process(delta: float) -> void:
	var target: float = 1.0 if is_visible_in_tree() and _is_hovered() else 0.0
	if is_equal_approx(_reveal_alpha, target):
		return
	var fade: float = style.hud_keepsake_tile_fade_sec
	_reveal_alpha = target if fade <= 0.0 else move_toward(_reveal_alpha, target, delta / fade)
	_place_tile()

func _is_hovered() -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return false
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())

# Above the row, left-aligned with it; below when it wouldn't fit above.
func _place_tile() -> void:
	if _tile == null:
		return
	_tile.visible = _reveal_alpha > 0.0
	_tile.modulate.a = _reveal_alpha
	if not _tile.visible:
		return
	if not is_equal_approx(_tile.tile_scale, style.hud_keepsake_tile_scale):
		_tile.tile_scale = style.hud_keepsake_tile_scale
	var tile_size: Vector2 = _tile.get_tile_size()
	var above: float = -tile_size.y - style.hud_keepsake_tile_gap_px
	if get_global_rect().position.y + above < 0.0:
		above = size.y + style.hud_keepsake_tile_gap_px
	_tile.position = Vector2(0.0, roundf(above))

func _draw() -> void:
	if _value_text.is_empty():
		return
	var baseline: float = style.row_baseline()
	var name_font: Font = style.hud_keepsake_font
	var name_size: int = style.hud_keepsake_size_px
	_draw_thumb(baseline, name_font, name_size)
	var left: float = _thumb_width()
	var width: float = InkType.width(name_font, _value_text, name_size)
	var hairline_top: float = baseline + style.hud_keepsake_hairline_gap_px
	var halo: float = maxf(style.hud_halo_px, 0.0)
	if halo > 0.0:
		style.draw_halo_run(self, name_font, _value_text, Vector2(left, baseline), name_size)
		draw_rect(Rect2(left - halo, hairline_top - halo, width + halo * 2.0, style.hud_keepsake_hairline_px + halo * 2.0), Color(style.hud_halo_color, style.hud_halo_color.a * style.hud_keepsake_hairline_alpha))
	InkType.draw_run(self, name_font, _value_text, Vector2(left, baseline), name_size, _ink)
	draw_rect(Rect2(left, hairline_top, width, style.hud_keepsake_hairline_px), Color(_ink, _ink.a * style.hud_keepsake_hairline_alpha))

# The art, cropped to a centred square, its bottom on the baseline - or
# the placeholder's tone - inside a thin ink edge.
func _draw_thumb(baseline: float, name_font: Font, name_size: int) -> void:
	var side: float = style.hud_keepsake_thumb_px
	var cap_centre: float = baseline - name_font.get_ascent(name_size) * 0.38
	var rect := Rect2(0.0, roundf(cap_centre - side / 2.0), side, side)
	var art: Texture2D = _keepsake.art if _keepsake != null else null
	if art != null:
		var full: Vector2 = art.get_size()
		var crop: float = minf(full.x, full.y)
		draw_texture_rect_region(art, rect, Rect2((full - Vector2(crop, crop)) / 2.0, Vector2(crop, crop)))
	else:
		draw_rect(rect, style.hud_keepsake_thumb_placeholder)
	var edge: float = style.hud_keepsake_thumb_edge_px
	if edge > 0.0:
		draw_rect(rect, _ink, false, edge)
