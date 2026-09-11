extends Node2D
class_name FieldBackdrop
# Self-contained field background, instanced by field_room.gd in place of
# its own procedural build when use_field_backdrop is true. Reads RoomState/
# RunState for placement but never reaches into field_room.gd or any node
# outside this scene's own subtree.

const FAR_RIDGE_TEXTURE_PATH := "res://assets/regions/beach/Backgrounds_Final/far_ridge_a.png"
const MID_HEADLAND_TEXTURE_PATH := "res://assets/regions/beach/Backgrounds_Final/mid_headland_a.png"
const GROUND_TILE_TEXTURE_PATH := "res://assets/regions/beach/Backgrounds_Final/ground_flat_tile.png"
# Row in ground_flat_tile.png where the painted ground line sits (given as
# y ~= 10-22 by the asset brief; 12 is the value specified to use).
const GROUND_TILE_LINE_Y := 12.0

# Same 6-texture set field_room.gd's cloud_textures export currently holds
# (assets/regions/beach/Clouds/cloud_00..05.png) - hardcoded here rather
# than exported, since clouds_scroll is the only cloud export this scene's
# API calls for.
const CLOUD_TEXTURE_PATHS := [
	"res://assets/regions/beach/Clouds/cloud_00.png",
	"res://assets/regions/beach/Clouds/cloud_01.png",
	"res://assets/regions/beach/Clouds/cloud_02.png",
	"res://assets/regions/beach/Clouds/cloud_03.png",
	"res://assets/regions/beach/Clouds/cloud_04.png",
	"res://assets/regions/beach/Clouds/cloud_05.png",
]
const CLOUD_BAND_TOP_Y := 40.0
const CLOUD_BAND_BOTTOM_Y := 340.0
const CLOUD_COLOR := Color(0.92, 0.93, 0.94, 0.45)

# Tower's width/taper aren't in this script's export list - ported as the
# same literal values field_room.tscn currently overrides them to
# (tower_width_fraction = 0.18, tower_taper = 0.7, tower_screen_x_fraction
# stays at its 0.72 script default) rather than turned into new exports.
const TOWER_WIDTH_FRACTION := 0.18
const TOWER_TAPER := 0.7
const TOWER_SCREEN_X_FRACTION := 0.72
const TOWER_COLOR := Color(0.775, 0.775, 0.775, 1)

# Hull specs, flattened to field_room.tscn's CURRENT effective values (its
# overrides on top of field_room.gd's own script defaults - see the
# investigation this pass is based on) - not re-exposed as new exports,
# per this script's fixed export list. y_offset below already folds in
# painted_preview_mid_y_offset's own tscn override (25.0) plus each hull's
# individual y_offset, since this scene has no separate shared-offset
# export. modulate already folds in painted_preview_mid_modulate's tscn
# override, which is (1,1,1,1) - the identity multiplier - so each hull's
# own modulate below is unchanged from field_room.tscn's value.
const HULL_SPECS := [
	{
		"path": "res://assets/regions/beach/OpeningRoom/Boats/hull_a_long.png",
		"height_frac": 0.06,
		"x_frac": -0.7,
		"y_offset": 5.0,
		"modulate": Color(0.91627353, 0.940525, 0.9822071, 1),
	},
	{
		"path": "res://assets/regions/beach/OpeningRoom/Boats/hull_b_listing.png",
		"height_frac": 0.09,
		"x_frac": 0.95,
		"y_offset": 23.0,
		"modulate": Color(0.972549, 0.98039216, 1, 1),
	},
	{
		"path": "res://assets/regions/beach/OpeningRoom/Boats/hull_c_upright.png",
		"height_frac": 0.1,
		"x_frac": 0.65,
		"y_offset": 31.0,
		"modulate": Color(0.91764706, 0.9411765, 0.98039216, 1),
	},
]

@export_group("Sky")
@export var sky_top_color: Color = Color(0.7, 0.74, 0.78, 1)
@export var sky_horizon_color: Color = Color(0.85, 0.86, 0.86, 1)

@export_group("Haze")
@export var haze_color: Color = Color(0.85, 0.86, 0.86, 1)
@export_range(0.0, 1.0, 0.01) var haze_far_alpha: float = 0.20
@export_range(0.0, 1.0, 0.01) var haze_mid_alpha: float = 0.20
@export_range(0.0, 1.0, 0.01) var haze_ground_alpha: float = 0.0

@export_group("Tower")
@export var tower_scroll: Vector2 = Vector2(0.0, 0.0)
@export_range(0.0, 1.0, 0.01) var tower_start_frac: float = 0.50
@export_range(0.0, 1.0, 0.01) var tower_end_frac: float = 0.56

@export_group("Far mass")
@export var far_mass_scroll: Vector2 = Vector2(0.15, 1.0)
@export_range(0.0, 1.0, 0.01) var far_mass_height_frac: float = 0.22
@export_range(0.0, 1.0, 0.01) var far_mass_x_frac: float = 0.62
@export var far_mass_base_y_offset: float = -4.0

@export_group("Mid mass")
@export var mid_mass_scroll: Vector2 = Vector2(0.45, 1.0)
@export_range(0.0, 1.0, 0.01) var mid_mass_height_frac: float = 0.30
@export_range(0.0, 1.0, 0.01) var mid_mass_x_frac: float = 0.35
@export var mid_mass_base_y_offset: float = 6.0
@export var hulls_enabled: bool = true

@export_group("Ground")
@export_range(0.0, 1.0, 0.01) var ground_height_frac: float = 0.42

@export_group("Foreground")
@export var foreground_scroll: Vector2 = Vector2(1.12, 1.0)

@export_group("Clouds")
@export var clouds_scroll: Vector2 = Vector2(0.15, 1.0)

@onready var sky: Parallax2D = $Sky
@onready var clouds: Parallax2D = $Clouds
@onready var tower: Parallax2D = $Tower
@onready var far_mass: Parallax2D = $FarMass
@onready var haze_far: Parallax2D = $HazeFar
@onready var mid_mass: Parallax2D = $MidMass
@onready var haze_mid: Parallax2D = $HazeMid
@onready var ground: Parallax2D = $Ground
@onready var haze_ground: Parallax2D = $HazeGround
@onready var foreground: Parallax2D = $Foreground

var sky_band_height: float = 0.0

func build() -> void:
	sky_band_height = RoomState.floor_line_y
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	for layer in [sky, clouds, tower, far_mass, haze_far, mid_mass, haze_mid, ground, haze_ground, foreground]:
		for child in layer.get_children():
			child.queue_free()

	_build_sky(viewport_size)
	_build_clouds()
	_build_tower(viewport_size)
	_build_far_mass()
	_build_haze(haze_far, haze_far_alpha, viewport_size)
	_build_mid_mass(viewport_size)
	_build_haze(haze_mid, haze_mid_alpha, viewport_size)
	_build_ground(viewport_size)
	_build_haze(haze_ground, haze_ground_alpha, viewport_size)
	foreground.scroll_scale = foreground_scroll

func _build_sky(viewport_size: Vector2) -> void:
	sky.scroll_scale = Vector2.ZERO
	var gradient := Gradient.new()
	gradient.set_color(0, sky_top_color)
	gradient.set_color(1, sky_horizon_color)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, RoomState.floor_line_y / maxf(viewport_size.y, 1.0))
	texture.width = maxi(int(viewport_size.x), 1)
	texture.height = maxi(int(viewport_size.y), 1)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sky.add_child(sprite)

func _build_clouds() -> void:
	clouds.scroll_scale = clouds_scroll
	var textures: Array[Texture2D] = []
	for path in CLOUD_TEXTURE_PATHS:
		var texture: Texture2D = load(path)
		if texture != null:
			textures.append(texture)
	if textures.is_empty():
		return
	# Fallback per this task's own "simple even spread" allowance - not a
	# faithful port of _add_clouds()'s drift/scatter/random-scale system,
	# which would run well past this pass's ~80 line budget for clouds.
	var count := textures.size()
	for i in count:
		var sprite := Sprite2D.new()
		sprite.texture = textures[i]
		sprite.modulate = CLOUD_COLOR
		sprite.position = Vector2(
			RoomState.room_width() * (float(i) + 0.5) / float(count),
			lerpf(CLOUD_BAND_TOP_Y, CLOUD_BAND_BOTTOM_Y, float(i % 3) / 2.0),
		)
		clouds.add_child(sprite)

func _build_tower(viewport_size: Vector2) -> void:
	tower.scroll_scale = tower_scroll
	var height_fraction := lerpf(tower_start_frac, tower_end_frac, RoomState.region_progress)
	var height := height_fraction * sky_band_height
	var base_y := RoomState.floor_line_y
	var top_y := base_y - height
	var cx := viewport_size.x * TOWER_SCREEN_X_FRACTION
	var base_half_width := TOWER_WIDTH_FRACTION * height / 2.0
	var top_half_width := base_half_width * TOWER_TAPER
	var polygon := Polygon2D.new()
	polygon.color = TOWER_COLOR
	polygon.polygon = PackedVector2Array([
		Vector2(cx - base_half_width, base_y),
		Vector2(cx + base_half_width, base_y),
		Vector2(cx + top_half_width, top_y),
		Vector2(cx - top_half_width, top_y),
	])
	tower.add_child(polygon)

func _build_far_mass() -> void:
	far_mass.scroll_scale = far_mass_scroll
	far_mass.repeat_size = Vector2.ZERO
	var texture: Texture2D = load(FAR_RIDGE_TEXTURE_PATH)
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	var target_height := far_mass_height_frac * sky_band_height
	var scale_factor := target_height / texture.get_size().y
	sprite.scale = Vector2(scale_factor, scale_factor)
	sprite.position = Vector2(
		RoomState.room_width() * far_mass_x_frac,
		RoomState.floor_line_y - target_height + far_mass_base_y_offset,
	)
	far_mass.add_child(sprite)

func _build_haze(layer: Parallax2D, alpha: float, viewport_size: Vector2) -> void:
	layer.scroll_scale = Vector2.ZERO
	var rect := ColorRect.new()
	rect.color = Color(haze_color.r, haze_color.g, haze_color.b, alpha)
	rect.position = Vector2.ZERO
	rect.size = viewport_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)

func _build_mid_mass(viewport_size: Vector2) -> void:
	mid_mass.scroll_scale = mid_mass_scroll
	mid_mass.repeat_size = Vector2.ZERO
	# Same room-type check _apply_painted_preview() uses for its own
	# opening-room hull branch.
	var is_opening_room := RunState.current_node == RunState.opening_node
	if is_opening_room and hulls_enabled:
		_build_hulls(viewport_size)
		return
	var texture: Texture2D = load(MID_HEADLAND_TEXTURE_PATH)
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	var target_height := mid_mass_height_frac * sky_band_height
	var scale_factor := target_height / texture.get_size().y
	sprite.scale = Vector2(scale_factor, scale_factor)
	sprite.position = Vector2(
		RoomState.room_width() * mid_mass_x_frac,
		RoomState.floor_line_y - target_height + mid_mass_base_y_offset,
	)
	mid_mass.add_child(sprite)

func _build_hulls(viewport_size: Vector2) -> void:
	for spec in HULL_SPECS:
		var texture: Texture2D = load(spec["path"])
		if texture == null:
			continue
		var target_height: float = viewport_size.y * spec["height_frac"]
		var scale_factor: float = target_height / texture.get_size().y
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.modulate = spec["modulate"]
		sprite.position = Vector2(
			spec["x_frac"] * viewport_size.x,
			RoomState.floor_line_y - target_height + spec["y_offset"],
		)
		mid_mass.add_child(sprite)

func _build_ground(viewport_size: Vector2) -> void:
	ground.scroll_scale = Vector2(1.0, 1.0)
	var texture: Texture2D = load(GROUND_TILE_TEXTURE_PATH)
	if texture == null:
		return
	var target_height := ground_height_frac * viewport_size.y
	var scale_factor := target_height / texture.get_size().y
	var repeat_unit_width := texture.get_size().x * scale_factor
	ground.repeat_size = Vector2(repeat_unit_width, 0.0)
	var total_span := RoomState.room_width() + viewport_size.x
	ground.repeat_times = int(ceil(total_span / repeat_unit_width)) + 1
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2(scale_factor, scale_factor)
	sprite.position = Vector2(0.0, RoomState.floor_line_y - GROUND_TILE_LINE_Y * scale_factor)
	ground.add_child(sprite)
