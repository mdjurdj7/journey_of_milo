extends Node3D
class_name FieldWind

# A floor's blowing sand (FloorData.wind, FloorWindData): made by
# RegionField after the scatter, it reads the ground once its relief is
# built and blows along the floor's one wind (RegionField.get_wind_
# direction()) until the scene goes.
#
# The gust: one value for the floor (get_gust(), RegionField.get_gust()),
# 0 calm to 1 full. A gust starts every gust_interval_s, drawn from the
# floor's own generator (the floor resource's path), rises, holds, falls.
# The streaks and plumes read it, and so do the tufts' sway (FieldScatter
# pushes it to tuft_card.gdshader).
#
# The map: the ground read at map_step_m over the relief - the drawn
# height, and whether its sand can lift (dry: drawn above the wet band
# (Ground.shore_slope_start over the sea, as FieldScatter's zones have
# it), off the ground's wet patches, not exposed rock (the ground
# shader's slope-times-rock_mask rule)). One texture (r height, g dry)
# both particle systems read. Crests: dry cells at least crest_min_
# fraction of the way from the sea to the floor's highest ground,
# standing crest_prominence_m over the ground crest_reach_m either side
# along some axis - a ridge, from the elevation the floor paints, never
# placed. Uploaded as a row of points (x, height, z).
#
# The layers: streaks - GPUParticles3D, born on dry sand round where the
# camera looks, riding the sand 0-0.3 m up, more and faster in a gust;
# plumes - off the crests, only while a gust blows; dust shadows - the
# ground shader's own (Ground.set_dust_shadow()), their travel pushed
# here. Both particle systems run wind_sand_particles.gdshader, drawn by
# wind_sand.gdshader.
#
# In a fight (RegionField.is_battle_open()) the streaks drop to
# battle_fraction and the plumes stop - streaks stay at the fighters'
# feet, nothing crosses them at height. Processes through the field's
# freeze, so the wind keeps on. Sits at the world origin unturned.

const PARTICLES_SHADER_PATH := "res://field/wind_sand_particles.gdshader"
const DRAW_SHADER_PATH := "res://field/wind_sand.gdshader"
# The most crest points uploaded - a long ridge is thinned evenly.
const MAX_CREST_POINTS := 2048

var _field: RegionField = null
var _data: FloorWindData = null
var _ground: Ground = null
var _sea_level: float = 0.0
var _rng := RandomNumberGenerator.new()

var _streaks: GPUParticles3D = null
var _plumes: GPUParticles3D = null
var _streak_process: ShaderMaterial = null
var _plume_process: ShaderMaterial = null
var _streak_draw: ShaderMaterial = null
var _plume_draw: ShaderMaterial = null

# The map and what it was built from (a change to these rebuilds it).
var _map_key: Array = []
var _map_origin: Vector2 = Vector2.ZERO
var _map_cols: int = 0
var _map_rows: int = 0
var _map_heights: PackedFloat32Array = PackedFloat32Array()
var _map_dry: PackedByteArray = PackedByteArray()
var _crests: PackedVector3Array = PackedVector3Array()
var _map_rebuild_queued: bool = false

# The gust's clock: seconds since the load, when the current gust started
# and how long it holds, and when the next starts.
var _time: float = 0.0
var _gust_start: float = -INF
var _gust_hold: float = 0.0
var _next_gust: float = 0.0
var _gust: float = 0.0
# How far the dust shadows have travelled, metres.
var _dust_travel: float = 0.0

func setup(field: RegionField, data: FloorWindData) -> void:
	_field = field
	_data = data
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ground = field.get_node_or_null(field.ground_path) as Ground
	var sea := field.get_node_or_null(^"Sea")
	_sea_level = float(sea.get("sea_level")) if sea != null else 0.0
	var floor_data: FloorData = field.get_floor_data()
	var floor_path: String = floor_data.resource_path if floor_data != null else ""
	_rng.seed = hash(floor_path + "#wind")
	_next_gust = maxf(data.first_gust_delay_s, 0.0) + _rng.randf_range(0.0, maxf(data.gust_interval_s.x, 0.0))
	if not data.changed.is_connected(_on_data_changed):
		data.changed.connect(_on_data_changed)
	if _ground != null and not _ground.relief_rebuilt.is_connected(_on_relief_rebuilt):
		_ground.relief_rebuilt.connect(_on_relief_rebuilt)
	_build_particles()
	_queue_map_rebuild()

func _exit_tree() -> void:
	if _data != null and _data.changed.is_connected(_on_data_changed):
		_data.changed.disconnect(_on_data_changed)
	if _ground != null:
		_ground.set_dust_shadow(0.0, 1.0, 1.0, Vector2.RIGHT, 0.0)

# 0 calm .. 1 a full gust.
func get_gust() -> float:
	return _gust

# The crest points the plumes rise from (x, height, z), for a check.
func get_crests() -> PackedVector3Array:
	return _crests

# Whether sand can lift at a point (the map's dry, nearest cell) - false
# off the map or before it is built.
func is_dry(p: Vector2) -> bool:
	var cell: int = _cell_at(p)
	return cell >= 0 and _map_dry[cell] != 0

func _on_data_changed() -> void:
	if _map_key != _current_map_key():
		_queue_map_rebuild()
	_apply_static()

func _on_relief_rebuilt() -> void:
	_map_key = []
	_queue_map_rebuild()

func _queue_map_rebuild() -> void:
	if _map_rebuild_queued:
		return
	_map_rebuild_queued = true
	call_deferred("_rebuild_map")

func _current_map_key() -> Array:
	return [_data.map_step_m, _data.crest_min_fraction, _data.crest_prominence_m, _data.crest_reach_m]

# --- The particles ---

func _build_particles() -> void:
	var process_shader := load(PARTICLES_SHADER_PATH) as Shader
	var draw_shader := load(DRAW_SHADER_PATH) as Shader
	_streak_process = ShaderMaterial.new()
	_streak_process.shader = process_shader
	_plume_process = ShaderMaterial.new()
	_plume_process.shader = process_shader
	_plume_process.set_shader_parameter("from_crests", true)
	_streak_draw = ShaderMaterial.new()
	_streak_draw.shader = draw_shader
	_plume_draw = ShaderMaterial.new()
	_plume_draw.shader = draw_shader
	_streaks = _make_particles("Streaks", _streak_process, _streak_draw)
	_plumes = _make_particles("Plumes", _plume_process, _plume_draw)
	_apply_static()

func _make_particles(node_name: String, process_material: ShaderMaterial, draw_material: ShaderMaterial) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.local_coords = false
	particles.fixed_fps = 0
	particles.interpolate = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.process_material = process_material
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = draw_material
	particles.draw_pass_1 = quad
	particles.emitting = false
	add_child(particles)
	return particles

# What changes only with an edit: counts, lives, sizes, speeds.
func _apply_static() -> void:
	if _streaks == null:
		return
	_streaks.amount = maxi(_data.streak_count, 1)
	_streaks.lifetime = maxf(_data.streak_lifetime_s, 0.1)
	_streaks.preprocess = _streaks.lifetime
	_plumes.amount = maxi(_data.plume_count, 1)
	_plumes.lifetime = maxf(_data.plume_lifetime_s, 0.1)
	_streak_process.set_shader_parameter("area_half", _data.streak_area_half_m)
	_streak_process.set_shader_parameter("speed", _data.streak_speed_mps)
	_streak_process.set_shader_parameter("height_range", _data.streak_height_m)
	_streak_process.set_shader_parameter("fade", _data.streak_fade)
	_streak_process.set_shader_parameter("peak_alpha", _data.streak_alpha)
	_plume_process.set_shader_parameter("speed", _data.plume_speed_mps)
	_plume_process.set_shader_parameter("rise", _data.plume_rise_mps)
	_plume_process.set_shader_parameter("height_range", _data.plume_height_m)
	_plume_process.set_shader_parameter("area_half", _data.plume_area_half_m)
	_plume_process.set_shader_parameter("fade", 0.3)
	_plume_process.set_shader_parameter("peak_alpha", _data.plume_alpha)
	for material: ShaderMaterial in [_streak_process, _plume_process]:
		material.set_shader_parameter("gust_speed_gain", _data.gust_speed_gain)
	_streak_draw.set_shader_parameter("size_m", _data.streak_size_m)
	_streak_draw.set_shader_parameter("grow", 1.0)
	_streak_draw.set_shader_parameter("darken_to", _data.streak_value)
	_streak_draw.set_shader_parameter("soft_depth_m", _data.streak_soft_depth_m)
	_plume_draw.set_shader_parameter("size_m", _data.plume_size_m)
	_plume_draw.set_shader_parameter("grow", _data.plume_grow)
	_plume_draw.set_shader_parameter("darken_to", _data.plume_value)
	_plume_draw.set_shader_parameter("soft_depth_m", _data.plume_soft_depth_m)

# --- The map ---

func _rebuild_map() -> void:
	_map_rebuild_queued = false
	if _field == null or _ground == null or not _ground.is_built():
		# The relief isn't built yet: relief_rebuilt brings us back.
		return
	var started: int = Time.get_ticks_msec()
	_map_key = _current_map_key()
	var step: float = maxf(_data.map_step_m, 0.25)
	var extent: Vector2 = _ground.relief_extent
	_map_origin = -extent * 0.5
	_map_cols = maxi(int(ceil(extent.x / step)) + 1, 2)
	_map_rows = maxi(int(ceil(extent.y / step)) + 1, 2)
	var count: int = _map_cols * _map_rows
	_map_heights.resize(count)
	_map_dry.resize(count)
	var highest: float = _sea_level
	for row in _map_rows:
		for col in _map_cols:
			var height: float = _ground.get_visible_height_at(_cell_point(col, row))
			_map_heights[row * _map_cols + col] = height
			highest = maxf(highest, height)
	var image := Image.create(_map_cols, _map_rows, false, Image.FORMAT_RGF)
	var wet_band: float = _ground.shore_slope_start
	var slope_full: float = _ground.rock_slope_min + maxf(_ground.rock_slope_blend, 0.001)
	for row in _map_rows:
		for col in _map_cols:
			var i: int = row * _map_cols + col
			var p: Vector2 = _cell_point(col, row)
			var height: float = _map_heights[i]
			var dry: bool = height - _sea_level > wet_band and _ground.get_wetness_at(p) < 0.5
			if dry:
				var stone: float = smoothstep(_ground.rock_slope_min, slope_full, _slope_degrees(col, row, step)) * _ground.get_rock_mask_at(p)
				dry = stone < 0.5
			_map_dry[i] = 1 if dry else 0
			image.set_pixel(col, row, Color(height, 1.0 if dry else 0.0, 0.0))
	_crests = _find_crests(step, highest)
	var map_texture := ImageTexture.create_from_image(image)
	var crest_image := Image.create(maxi(_crests.size(), 1), 1, false, Image.FORMAT_RGBAF)
	for i in _crests.size():
		var c: Vector3 = _crests[i]
		crest_image.set_pixel(i, 0, Color(c.x, c.y, c.z, 1.0))
	var crest_texture := ImageTexture.create_from_image(crest_image)
	for material: ShaderMaterial in [_streak_process, _plume_process]:
		material.set_shader_parameter("ground_map", map_texture)
		material.set_shader_parameter("map_origin", _map_origin)
		material.set_shader_parameter("map_step", step)
		material.set_shader_parameter("map_cells", Vector2(_map_cols, _map_rows))
		material.set_shader_parameter("crest_points", crest_texture)
		material.set_shader_parameter("crest_count", _crests.size())
	var lowest: float = _sea_level - 2.0
	var bounds := AABB(Vector3(_map_origin.x, lowest, _map_origin.y), Vector3(extent.x, highest - lowest + 6.0, extent.y))
	_streaks.visibility_aabb = bounds
	_plumes.visibility_aabb = bounds
	_push_live(0.0)
	_streaks.restart()
	_streaks.emitting = true
	_plumes.emitting = not _crests.is_empty()
	print("FieldWind: %d x %d map, %d crest points, in %d ms" % [_map_cols, _map_rows, _crests.size(), Time.get_ticks_msec() - started])

func _cell_point(col: int, row: int) -> Vector2:
	var step: float = maxf(_data.map_step_m, 0.25)
	return _map_origin + Vector2(float(col) * step, float(row) * step)

func _cell_at(p: Vector2) -> int:
	if _map_cols == 0:
		return -1
	var step: float = maxf(_data.map_step_m, 0.25)
	var col: int = roundi((p.x - _map_origin.x) / step)
	var row: int = roundi((p.y - _map_origin.y) / step)
	if col < 0 or row < 0 or col >= _map_cols or row >= _map_rows:
		return -1
	return row * _map_cols + col

func _height_cell(col: int, row: int) -> float:
	return _map_heights[clampi(row, 0, _map_rows - 1) * _map_cols + clampi(col, 0, _map_cols - 1)]

func _slope_degrees(col: int, row: int, step: float) -> float:
	var dx: float = (_height_cell(col + 1, row) - _height_cell(col - 1, row)) / (2.0 * step)
	var dz: float = (_height_cell(col, row + 1) - _height_cell(col, row - 1)) / (2.0 * step)
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))

# Dry cells high enough that stand over the ground crest_reach_m either
# side along one of four axes - thinned evenly to MAX_CREST_POINTS.
func _find_crests(step: float, highest: float) -> PackedVector3Array:
	var found := PackedVector3Array()
	var floor_height: float = _sea_level + _data.crest_min_fraction * (highest - _sea_level)
	var reach: int = maxi(roundi(_data.crest_reach_m / step), 1)
	var axes: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for row in range(reach, _map_rows - reach):
		for col in range(reach, _map_cols - reach):
			var i: int = row * _map_cols + col
			var height: float = _map_heights[i]
			if _map_dry[i] == 0 or height < floor_height:
				continue
			for axis in axes:
				var ahead: float = _height_cell(col + axis.x * reach, row + axis.y * reach)
				var behind: float = _height_cell(col - axis.x * reach, row - axis.y * reach)
				if height - ahead >= _data.crest_prominence_m and height - behind >= _data.crest_prominence_m:
					var p: Vector2 = _cell_point(col, row)
					found.append(Vector3(p.x, height, p.y))
					break
	if found.size() <= MAX_CREST_POINTS:
		return found
	var thinned := PackedVector3Array()
	var stride: float = float(found.size()) / float(MAX_CREST_POINTS)
	for k in MAX_CREST_POINTS:
		thinned.append(found[int(float(k) * stride)])
	return thinned

# --- Every frame ---

func _process(delta: float) -> void:
	if _field == null or _data == null:
		return
	_advance_gust(delta)
	_push_live(delta)

# Start the next gust when its time comes; the value: eased up over
# gust_rise_s, held, eased down over gust_fall_s.
func _advance_gust(delta: float) -> void:
	_time += delta
	if _time >= _next_gust:
		_gust_start = _next_gust
		_gust_hold = _rng.randf_range(_data.gust_hold_s.x, maxf(_data.gust_hold_s.y, _data.gust_hold_s.x))
		var length: float = _data.gust_rise_s + _gust_hold + _data.gust_fall_s
		var interval: float = _rng.randf_range(_data.gust_interval_s.x, maxf(_data.gust_interval_s.y, _data.gust_interval_s.x))
		_next_gust = _gust_start + maxf(interval, length)
	var t: float = _time - _gust_start
	var rise: float = maxf(_data.gust_rise_s, 0.001)
	var fall: float = maxf(_data.gust_fall_s, 0.001)
	if t < 0.0:
		_gust = 0.0
	elif t < rise:
		_gust = smoothstep(0.0, 1.0, t / rise)
	elif t < rise + _gust_hold:
		_gust = 1.0
	elif t < rise + _gust_hold + fall:
		_gust = 1.0 - smoothstep(0.0, 1.0, (t - rise - _gust_hold) / fall)
	else:
		_gust = 0.0

func _push_live(delta: float) -> void:
	if _streaks == null:
		return
	var wind3: Vector3 = _field.get_wind_direction()
	var wind := Vector2(wind3.x, wind3.z)
	var battle: bool = _field.is_battle_open()
	var focus: Vector2 = _camera_focus()
	for material: ShaderMaterial in [_streak_process, _plume_process]:
		material.set_shader_parameter("wind_dir", wind)
		material.set_shader_parameter("gust", _gust)
	_streak_process.set_shader_parameter("area_center", focus)
	_plume_process.set_shader_parameter("area_center", focus)
	_streak_draw.set_shader_parameter("wind_dir", wind)
	_plume_draw.set_shader_parameter("wind_dir", wind)
	var streak_ratio: float = lerpf(_data.streak_calm_fraction, 1.0, _gust)
	if battle:
		streak_ratio *= _data.battle_fraction
	_streaks.amount_ratio = clampf(streak_ratio, 0.0, 1.0)
	_plumes.amount_ratio = 0.0 if battle else clampf(_gust, 0.0, 1.0)
	_dust_travel += _data.dust_shadow_speed_mps * (1.0 + _gust * _data.gust_speed_gain) * delta
	if _ground != null:
		_ground.set_dust_shadow(_data.dust_shadow_strength, _data.dust_shadow_scale_m, _data.dust_shadow_stretch, wind, _dust_travel)

# Where the camera's centre ray meets the ground (taken flat at the
# camera's own ground height under it), or a little ahead of it when it
# looks too near level for that.
func _camera_focus() -> Vector2:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		var spawn: Vector3 = _field.get_spawn_position()
		return Vector2(spawn.x, spawn.z)
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var ground_y: float = _ground.get_height_at(Vector2(origin.x, origin.z)) if _ground != null else 0.0
	if forward.y < -0.05:
		var hit: Vector3 = origin + forward * ((origin.y - ground_y) / -forward.y)
		return Vector2(hit.x, hit.z)
	var flat := Vector2(forward.x, forward.z)
	flat = flat.normalized() if flat.length() > 0.0001 else Vector2(0.0, -1.0)
	return Vector2(origin.x, origin.z) + flat * 10.0
