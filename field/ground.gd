extends StaticBody3D
class_name Ground

@export var ground_color: Color = Color(0.72, 0.73, 0.66):
	set(value):
		ground_color = value
		_apply_uniform("dry_color", value)

@export var plane_size: Vector2 = Vector2(500.0, 500.0)
@export var dressing_subdivisions: Vector2i = Vector2i(4, 4)

# Fine-subdivided inner plane sized to the playable area, so relief
# detail exists where the Wanderer actually walks; the outer dressing
# plane (plane_size, above) stays coarse. GDScript-only now (see
# get_height_at()) - no longer pushed to the shader, which no longer
# displaces vertices at all.
@export var relief_extent: Vector2 = Vector2(80.0, 50.0):
	set(value):
		relief_extent = value
		_rebuild_ground_mesh_and_collision()
@export var relief_subdivisions: Vector2i = Vector2i(40, 25):
	set(value):
		relief_subdivisions = value
		_rebuild_ground_mesh_and_collision()

@export var near_color: Color = Color(1.0, 1.0, 1.0):
	set(value):
		near_color = value
		_apply_uniform("near_color", value)
@export var far_color: Color = Color(0.7, 0.7, 0.72):
	set(value):
		far_color = value
		_apply_uniform("far_color", value)
@export var near_distance: float = 5.0:
	set(value):
		near_distance = value
		_apply_uniform("near_distance", value)
@export var far_distance: float = 60.0:
	set(value):
		far_distance = value
		_apply_uniform("far_distance", value)

@export var wetness_scale: float = 30.0:
	set(value):
		wetness_scale = value
		_apply_uniform("wetness_scale", value)
		_rebuild_ground_mesh_and_collision()
@export var wetness_amount: float = 0.4:
	set(value):
		wetness_amount = value
		_apply_uniform("wetness_amount", value)
		_rebuild_ground_mesh_and_collision()
@export var wet_color: Color = Color(0.35, 0.38, 0.40):
	set(value):
		wet_color = value
		_apply_uniform("wet_color", value)
@export var wet_roughness: float = 0.15:
	set(value):
		wet_roughness = value
		_apply_uniform("wet_roughness", value)
@export var wet_specular: float = 0.4:
	set(value):
		wet_specular = value
		_apply_uniform("wet_specular", value)

@export var pool_threshold: float = 0.75:
	set(value):
		pool_threshold = value
		_apply_uniform("pool_threshold", value)
@export var pool_edge_width: float = 0.15:
	set(value):
		pool_edge_width = value
		_apply_uniform("pool_edge_width", value)
@export var pool_color: Color = Color(0.696, 0.704, 0.68):
	set(value):
		pool_color = value
		_apply_uniform("pool_color", value)
@export var pool_roughness: float = 0.35:
	set(value):
		pool_roughness = value
		_apply_uniform("pool_roughness", value)

# GDScript-only (see get_height_at()) - relief is baked into the mesh/
# collision at rebuild time, not pushed to the shader as a uniform.
@export var relief_amplitude: float = 0.3:
	set(value):
		relief_amplitude = value
		_rebuild_ground_mesh_and_collision()
@export var relief_noise_scale: float = 4.0:
	set(value):
		relief_noise_scale = value
		_rebuild_ground_mesh_and_collision()
# Relief height fades to zero over the last relief_edge_fade meters inside
# relief_extent's edges, so the fine relief mesh meets the flat outer
# dressing plane flush instead of leaving a seam at the boundary.
@export var relief_edge_fade: float = 4.0:
	set(value):
		relief_edge_fade = value
		_rebuild_ground_mesh_and_collision()

# Drift lines: a few faint bands running parallel to the shore, marking
# where wrack will sit later. Spaced inland from the water line, wobbled
# so they don't read as ruled lines, and faded out after drift_line_count
# of them so only a handful ever show.
@export var drift_line_spacing: float = 6.0:
	set(value):
		drift_line_spacing = value
		_apply_uniform("drift_line_spacing", value)
@export var drift_line_width: float = 1.0:
	set(value):
		drift_line_width = value
		_apply_uniform("drift_line_width", value)
@export var drift_line_wobble: float = 1.5:
	set(value):
		drift_line_wobble = value
		_apply_uniform("drift_line_wobble", value)
@export var drift_line_wobble_scale: float = 10.0:
	set(value):
		drift_line_wobble_scale = value
		_apply_uniform("drift_line_wobble_scale", value)
@export var drift_line_count: int = 3:
	set(value):
		drift_line_count = value
		_apply_uniform("drift_line_count", value)
@export var drift_line_strength: float = 0.05:
	set(value):
		drift_line_strength = value
		_apply_uniform("drift_line_strength", value)
@export var drift_line_color: Color = Color(0.55, 0.48, 0.4):
	set(value):
		drift_line_color = value
		_apply_uniform("drift_line_color", value)

# Ripple marks: faint, fine-scale directional noise in wet sand, perpendicular
# to the shore. A value shift, not a texture.
@export var ripple_scale: float = 0.4:
	set(value):
		ripple_scale = value
		_apply_uniform("ripple_scale", value)
@export var ripple_stretch: float = 6.0:
	set(value):
		ripple_stretch = value
		_apply_uniform("ripple_stretch", value)
@export var ripple_strength: float = 0.02:
	set(value):
		ripple_strength = value
		_apply_uniform("ripple_strength", value)

# Wet band: within shore_slope_start of the water line, sand wetness is
# pushed to 1.0 so it reflects like the water does. water_line_z/
# water_forward_z (pushed once in _ready(), below) come from Sea and
# RegionField, not assumed.
@export var shore_slope_start: float = 8.0:
	set(value):
		shore_slope_start = value
		_apply_uniform("shore_slope_start", value)
@export var region_field_path: NodePath = ^".."
@export var sea_path: NodePath = ^"../Sea"

# Draws a small sphere at get_height_at() for every vertex of the current
# relief grid - the exact same samples the relief mesh and its
# HeightMapShape3D are built from (see _relief_heights below), so a sphere
# floating off the rendered surface, or off where the Wanderer/an enemy
# actually stands, points at a real bug rather than requiring a guess.
@export var draw_ground_debug: bool = false:
	set(value):
		draw_ground_debug = value
		_rebuild_ground_debug()

var _material: ShaderMaterial
# Guards _rebuild_ground_mesh_and_collision() against firing from a relief
# export's own setter mid-deserialization, before collision_shape (an
# @onready var) is populated - exported properties are assigned as the
# scene loads, which happens before _ready() (and its @onready resolution)
# runs at all. Same reasoning as _apply_uniform()'s own "if _material:"
# guard, just for node references instead of the material.
var _ready_done: bool = false
var _relief_mesh_instance: MeshInstance3D
# The one shared array of height samples: built once per rebuild by
# _sample_relief_heights(), then fed as-is into both the relief mesh's
# vertices and the HeightMapShape3D's map_data (see _apply_relief_mesh()/
# _apply_relief_collision()) and reused again by _rebuild_ground_debug() -
# never resampled independently by any of the three, which is the whole
# point: one source of truth instead of three approximations of it.
var _relief_heights: PackedFloat32Array = PackedFloat32Array()
var _relief_cols: int = 0
var _relief_rows: int = 0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	# Same reasoning as FieldEnemy's own disable_mode override: RegionField's
	# battle freeze would otherwise remove Ground from the physics space
	# entirely (disable_mode's default, REMOVE), and the targeting raycast
	# needs solid ground behind/around enemies to behave sanely too.
	disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC

	_material = ShaderMaterial.new()
	_material.shader = load("res://field/ground.gdshader")
	_apply_all_uniforms()

	_relief_mesh_instance = MeshInstance3D.new()
	# Cosmetic-only, render-side nudge: _rebuild_dressing_frame() keeps the
	# coarse dressing mesh entirely OUTSIDE relief_extent (see its own doc
	# for why - it used to fully underlie the relief mesh at y=0 and
	# occlude every negative/sunk dip, which was the real cause of "buried"
	# debug spheres), so the only remaining coincidence is the shared
	# boundary edge, where the relief mesh's own edge-faded-to-zero border
	# meets the dressing frame's inner edge at the same height - this nudge
	# keeps the relief mesh on top there instead of z-fighting the seam.
	# Deliberately NOT reflected in get_height_at()/collision - baking it in
	# there would reintroduce a real (if tiny) visual/collision mismatch,
	# the exact thing this rebuild exists to eliminate.
	_relief_mesh_instance.position.y = 0.02
	add_child(_relief_mesh_instance)

	_ready_done = true
	_rebuild_ground_mesh_and_collision()
	_debug_assert_height_matches_shader_math()

	_apply_water_line_uniforms()

# RegionField.get_forward() and Sea.get_near_edge_z() are both lazy and
# safe to call regardless of node-ready order (see their own comments),
# so this can run directly from _ready() with no deferral needed.
func _apply_water_line_uniforms() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	var sea := get_node_or_null(sea_path) as Sea
	var forward: Vector3 = region_field.get_forward() if region_field else Vector3.FORWARD
	var water_line_z: float = sea.get_near_edge_z() if sea else 0.0
	_apply_uniform("water_line_z", water_line_z)
	_apply_uniform("water_forward_z", forward.z)

func _apply_all_uniforms() -> void:
	_apply_uniform("dry_color", ground_color)
	_apply_uniform("near_color", near_color)
	_apply_uniform("far_color", far_color)
	_apply_uniform("near_distance", near_distance)
	_apply_uniform("far_distance", far_distance)
	_apply_uniform("wetness_scale", wetness_scale)
	_apply_uniform("wetness_amount", wetness_amount)
	_apply_uniform("wet_color", wet_color)
	_apply_uniform("wet_roughness", wet_roughness)
	_apply_uniform("wet_specular", wet_specular)
	_apply_uniform("shore_slope_start", shore_slope_start)
	_apply_uniform("pool_threshold", pool_threshold)
	_apply_uniform("pool_edge_width", pool_edge_width)
	_apply_uniform("pool_color", pool_color)
	_apply_uniform("pool_roughness", pool_roughness)
	_apply_uniform("drift_line_spacing", drift_line_spacing)
	_apply_uniform("drift_line_width", drift_line_width)
	_apply_uniform("drift_line_wobble", drift_line_wobble)
	_apply_uniform("drift_line_wobble_scale", drift_line_wobble_scale)
	_apply_uniform("drift_line_count", drift_line_count)
	_apply_uniform("drift_line_strength", drift_line_strength)
	_apply_uniform("drift_line_color", drift_line_color)
	_apply_uniform("ripple_scale", ripple_scale)
	_apply_uniform("ripple_stretch", ripple_stretch)
	_apply_uniform("ripple_strength", ripple_strength)

func _apply_uniform(uniform_name: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(uniform_name, value)

# Called by region_sky.gd so the standing-pool color always tracks the
# sky's horizon color without manual duplication. pool_color's own
# export default above is the fallback if no sky node pushes a value.
# Darkened, not a direct copy: horizon_color at full brightness blows
# pools out white once they're catching sky-colored specular. Pools are
# meant to be the darkest thing on the ground, never the brightest.
func set_pool_color_from_sky(sky_horizon_color: Color) -> void:
	pool_color = Color(
		sky_horizon_color.r * 0.75,
		sky_horizon_color.g * 0.75,
		sky_horizon_color.b * 0.75,
		sky_horizon_color.a
	)

# --- Relief height/wetness: the one source of truth for the ground ---
#
# get_height_at() and get_wetness_at() are the ONLY place relief math is
# evaluated as a continuous function. ground.gdshader no longer displaces
# vertices or computes relief at all - _rebuild_ground_mesh_and_collision()
# below samples get_height_at() once, on a grid, and bakes the result into
# both the relief mesh's vertices/normals and its HeightMapShape3D from the
# exact same array, so render and collision can no longer disagree the way
# they used to (a sparse render mesh linearly interpolating between distant
# vertices vs. collision separately re-evaluating the exact procedural
# value at a totally different point - two different approximations of the
# same field, guaranteed to disagree almost everywhere). Sample the grid
# finer (relief_subdivisions) if a query point still needs to fall closer
# to an authored vertex.
#
# get_height_at() deliberately omits one thing the shader's old vertex()
# displacement had: the camera-distance relief_fade (formerly relief_fade_
# start/relief_fade_end). That fade only ever existed to flatten distant
# relief for render cost - now that relief is baked into real mesh
# geometry once (not recomputed per-frame per-camera-position), that
# concept has nowhere left to plug in, and both exports were removed as
# dead code alongside it.
#
# Shore slope (shore_t()/water_line_z in the shader) was NOT moved in here
# despite being asked for, because it was never a height effect to begin
# with: the shader's own relief_height() always read the plain
# wetness_mask(), never the shore-boosted sand_wetness_mask() shore_t()
# feeds into - shoreline proximity only ever affected fragment coloring.
# Moving it into get_height_at() would invent a new "beach slopes into the
# water" effect the shader never had, rather than reproducing an existing
# one - out of scope for a refactor about making collision agree with what
# already rendered. get_wetness_at() below is the same story: it mirrors
# the plain wetness_mask() relief_height() itself sinks by, not the shore-
# boosted variant. Flag this if an actual sloped shoreline was wanted.
func get_height_at(world_xz: Vector2) -> float:
	return _relief_height(world_xz) * _relief_edge_fade_factor(world_xz)

# Same port discipline as get_height_at() - mirrors ground.gdshader's own
# wetness_mask() exactly (see get_height_at()'s doc for why the shore-
# boosted sand_wetness_mask() is deliberately not what this exposes).
func get_wetness_at(world_xz: Vector2) -> float:
	return _wetness_mask(world_xz)

func _hash(p: Vector2) -> float:
	var x: float = fposmod(p.x * 123.34, 1.0)
	var y: float = fposmod(p.y * 456.21, 1.0)
	var d: float = x * (x + 45.32) + y * (y + 45.32)
	x += d
	y += d
	return fposmod(x * y, 1.0)

func _value_noise(p: Vector2) -> float:
	var i: Vector2 = Vector2(floor(p.x), floor(p.y))
	var f: Vector2 = p - i
	f = Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var a: float = _hash(i)
	var b: float = _hash(i + Vector2(1.0, 0.0))
	var c: float = _hash(i + Vector2(0.0, 1.0))
	var d: float = _hash(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

func _wetness_mask(world_xz: Vector2) -> float:
	var scale: float = maxf(wetness_scale, 0.001)
	var n: float = _value_noise(world_xz / scale)
	return clampf(n + (wetness_amount - 0.5) * 2.0, 0.0, 1.0)

func _relief_height(world_xz: Vector2) -> float:
	var wetness: float = _wetness_mask(world_xz)
	var noise_scale: float = maxf(relief_noise_scale, 0.001)
	var bump: float = (_value_noise(world_xz / noise_scale) - 0.5) * 2.0
	return bump * relief_amplitude - wetness * relief_amplitude

func _relief_edge_fade_factor(world_xz: Vector2) -> float:
	var half_extent: Vector2 = relief_extent * 0.5
	var edge_dist: float = minf(half_extent.x - absf(world_xz.x), half_extent.y - absf(world_xz.y))
	return smoothstep(0.0, maxf(relief_edge_fade, 0.001), edge_dist)

# Sample points and their expected get_height_at() result, computed once
# by an independent re-port of the same shader math (in Node.js, not this
# file) at ground.gd's own declared export defaults - see the constants
# just below. Only meaningful while every export listed there still
# matches its default: _debug_assert_height_matches_shader_math() skips
# the whole comparison the moment any of them has been tuned away from
# that, so editing relief in the Remote tab never trips a false failure.
const DEBUG_DEFAULT_WETNESS_SCALE: float = 30.0
const DEBUG_DEFAULT_WETNESS_AMOUNT: float = 0.4
const DEBUG_DEFAULT_RELIEF_NOISE_SCALE: float = 4.0
const DEBUG_DEFAULT_RELIEF_AMPLITUDE: float = 0.3
const DEBUG_DEFAULT_RELIEF_EXTENT: Vector2 = Vector2(80.0, 50.0)
const DEBUG_DEFAULT_RELIEF_EDGE_FADE: float = 4.0
const DEBUG_REFERENCE_SAMPLES: Dictionary = {
	Vector2(0.0, 0.0): -0.3,
	Vector2(20.0, -12.0): -0.05804631,
	Vector2(38.0, 0.0): 0.0275360891,
	Vector2(100.0, 100.0): 0.0,
	Vector2(-15.0, 8.0): -0.2684771334,
}

func _debug_assert_height_matches_shader_math() -> void:
	if not OS.is_debug_build():
		return
	var at_defaults: bool = (
		is_equal_approx(wetness_scale, DEBUG_DEFAULT_WETNESS_SCALE)
		and is_equal_approx(wetness_amount, DEBUG_DEFAULT_WETNESS_AMOUNT)
		and is_equal_approx(relief_noise_scale, DEBUG_DEFAULT_RELIEF_NOISE_SCALE)
		and is_equal_approx(relief_amplitude, DEBUG_DEFAULT_RELIEF_AMPLITUDE)
		and relief_extent.is_equal_approx(DEBUG_DEFAULT_RELIEF_EXTENT)
		and is_equal_approx(relief_edge_fade, DEBUG_DEFAULT_RELIEF_EDGE_FADE)
	)
	if not at_defaults:
		return
	for world_xz: Vector2 in DEBUG_REFERENCE_SAMPLES:
		var expected: float = DEBUG_REFERENCE_SAMPLES[world_xz]
		var actual: float = get_height_at(world_xz)
		assert(absf(actual - expected) < 0.0001, "Ground.get_height_at() diverged from the ground.gdshader reference at %s: expected %f, got %f" % [world_xz, expected, actual])

# --- Relief mesh + collision: built together from one sample array ---
#
# _sample_relief_heights() is the ONLY place that calls get_height_at() for
# the mesh/collision rebuild - its result is handed unmodified to both
# _apply_relief_mesh() and _apply_relief_collision(), and cached in
# _relief_heights/_relief_cols/_relief_rows for _rebuild_ground_debug() to
# reuse too. The area beyond relief_extent (out to plane_size) is four
# BoxShape3D "frame" strips instead of a single infinite
# WorldBoundaryShape3D. That's a real replacement, not just an addition:
# an infinite flat plane would still be solid at y=0 everywhere, including
# under the heightmap's negative (wetness-sunk) dips, and a CharacterBody3D
# falling onto a dip would stop on the flat plane before ever reaching the
# heightmap's lower surface - silently erasing every sunk/pool area's
# actual collision. Confining the flat shapes to a frame around
# relief_extent, with no coverage inside it, is what lets dips work.
const OUTER_FRAME_NODE_PREFIX: String = "OuterFrame_"
const OUTER_FRAME_THICKNESS: float = 2.0
const DRESSING_FRAME_NODE_PREFIX: String = "DressingFrame_"
const GROUND_DEBUG_NODE_NAME: String = "GroundDebugSpheres"
const GROUND_DEBUG_SPHERE_RADIUS: float = 0.15

func _rebuild_ground_mesh_and_collision() -> void:
	if not _ready_done:
		return

	var cols: int = relief_subdivisions.x + 2
	var rows: int = relief_subdivisions.y + 2
	var heights: PackedFloat32Array = _sample_relief_heights(cols, rows)
	_relief_cols = cols
	_relief_rows = rows
	_relief_heights = heights

	_apply_relief_mesh(cols, rows, heights)
	_apply_relief_collision(cols, rows, heights)
	_clear_outer_frame()
	_build_outer_flat_frame()
	_rebuild_dressing_frame()
	_rebuild_ground_debug()

# The one shared mapping from a relief grid index to its world XZ - every
# consumer (sampling, mesh vertices, the collision transform's spacing, the
# debug spheres) calls this or _relief_grid_spacing() below rather than
# recomputing half-extent/spacing inline, so none of them can drift from
# the others by so much as a rounding difference. col=0/row=0 is the
# grid's own corner; the whole grid spans exactly relief_extent, centered
# on Ground's own origin.
func _relief_grid_spacing(cols: int, rows: int) -> Vector2:
	return Vector2(relief_extent.x / float(cols - 1), relief_extent.y / float(rows - 1))

func _relief_grid_to_world_xz(col: int, row: int, cols: int, rows: int) -> Vector2:
	var spacing: Vector2 = _relief_grid_spacing(cols, rows)
	var half_extent: Vector2 = relief_extent * 0.5
	return Vector2(-half_extent.x + float(col) * spacing.x, -half_extent.y + float(row) * spacing.y)

# The one and only sampling pass: get_height_at() at every grid point over
# relief_extent, cols x rows samples (relief_subdivisions + 2 per axis,
# matching PlaneMesh's own "N subdivisions -> N+2 vertices" convention so
# the mesh keeps roughly its old density). Row-major, z outer / x inner
# (index = row * cols + col) - _apply_relief_mesh(), _apply_relief_
# collision(), and _rebuild_ground_debug() all assume this exact layout.
func _sample_relief_heights(cols: int, rows: int) -> PackedFloat32Array:
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(cols * rows)
	for row in rows:
		for col in cols:
			var world_xz: Vector2 = _relief_grid_to_world_xz(col, row, cols, rows)
			heights[row * cols + col] = get_height_at(world_xz)
	return heights

# Builds the relief ArrayMesh directly from heights - no PlaneMesh, no
# shader displacement. Normals come from the central-difference gradient
# of this same array (one-sided at the grid's own edges), the same
# formula ground.gdshader's old vertex() used, just evaluated over the
# mesh's real spacing instead of a small epsilon.
func _apply_relief_mesh(cols: int, rows: int, heights: PackedFloat32Array) -> void:
	var spacing: Vector2 = _relief_grid_spacing(cols, rows)
	var spacing_x: float = spacing.x
	var spacing_z: float = spacing.y

	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	vertices.resize(cols * rows)
	normals.resize(cols * rows)

	for row in rows:
		for col in cols:
			var world_xz: Vector2 = _relief_grid_to_world_xz(col, row, cols, rows)
			var index: int = row * cols + col
			vertices[index] = Vector3(world_xz.x, heights[index], world_xz.y)

			var col_left: int = maxi(col - 1, 0)
			var col_right: int = mini(col + 1, cols - 1)
			var row_down: int = maxi(row - 1, 0)
			var row_up: int = mini(row + 1, rows - 1)
			var h_left: float = heights[row * cols + col_left]
			var h_right: float = heights[row * cols + col_right]
			var h_down: float = heights[row_down * cols + col]
			var h_up: float = heights[row_up * cols + col]
			var dx_span: float = spacing_x * float(col_right - col_left)
			var dz_span: float = spacing_z * float(row_up - row_down)
			var slope_x: float = (h_right - h_left) / dx_span if dx_span > 0.0001 else 0.0
			var slope_z: float = (h_up - h_down) / dz_span if dz_span > 0.0001 else 0.0
			normals[index] = Vector3(-slope_x, 1.0, -slope_z).normalized()

	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((cols - 1) * (rows - 1) * 6)
	var tri: int = 0
	for row in rows - 1:
		for col in cols - 1:
			var top_left: int = row * cols + col
			var top_right: int = top_left + 1
			var bottom_left: int = (row + 1) * cols + col
			var bottom_right: int = bottom_left + 1

			indices[tri] = top_left
			indices[tri + 1] = bottom_left
			indices[tri + 2] = top_right
			indices[tri + 3] = top_right
			indices[tri + 4] = bottom_left
			indices[tri + 5] = bottom_right
			tri += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	array_mesh.surface_set_material(0, _material)
	_relief_mesh_instance.mesh = array_mesh

# HeightMapShape3D's own grid is always 1 local unit between samples (no
# separate cell-size property) - collision_shape's transform is scaled to
# spacing_x/spacing_z so its native grid lands on the exact same world
# positions _apply_relief_mesh() just placed vertices at, using the exact
# same heights array (not recomputed).
func _apply_relief_collision(cols: int, rows: int, heights: PackedFloat32Array) -> void:
	var height_shape := HeightMapShape3D.new()
	height_shape.map_width = cols
	height_shape.map_depth = rows
	height_shape.map_data = heights

	var spacing: Vector2 = _relief_grid_spacing(cols, rows)
	collision_shape.transform = Transform3D(Basis.from_scale(Vector3(spacing.x, 1.0, spacing.y)), Vector3.ZERO)
	collision_shape.shape = height_shape

func _clear_outer_frame() -> void:
	for child in get_children():
		if String(child.name).begins_with(OUTER_FRAME_NODE_PREFIX):
			child.queue_free()

# Small unshaded spheres at get_height_at() over the exact same grid
# _relief_heights already holds - reused, not resampled, so this always
# shows literally the same data the mesh/collision were built from. Placed
# directly under Ground (not _relief_mesh_instance), so they sit at the
# collision's actual height, WITHOUT _relief_mesh_instance's own +0.02
# cosmetic z-fight nudge - expect the rendered surface to sit ~2cm above
# these spheres everywhere, that's the known offset, not a bug. If a
# sphere sits any further from the rendered surface than that, or a
# character doesn't stand on the sphere nearest it, the mismatch is in the
# ArrayMesh/HeightMapShape3D construction (winding, indexing, transform),
# not in get_height_at() itself.
func _rebuild_ground_debug() -> void:
	if not _ready_done:
		return
	var existing := get_node_or_null(GROUND_DEBUG_NODE_NAME)
	if existing:
		existing.queue_free()
	if not draw_ground_debug or _relief_heights.is_empty():
		return

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = GROUND_DEBUG_SPHERE_RADIUS
	sphere_mesh.height = GROUND_DEBUG_SPHERE_RADIUS * 2.0
	var debug_material := StandardMaterial3D.new()
	debug_material.albedo_color = Color(1.0, 0.15, 0.7)
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_mesh.material = debug_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sphere_mesh
	multimesh.instance_count = _relief_cols * _relief_rows

	for row in _relief_rows:
		for col in _relief_cols:
			var world_xz: Vector2 = _relief_grid_to_world_xz(col, row, _relief_cols, _relief_rows)
			var index: int = row * _relief_cols + col
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(world_xz.x, _relief_heights[index], world_xz.y)))

	var multimesh_instance := MultiMeshInstance3D.new()
	multimesh_instance.name = GROUND_DEBUG_NODE_NAME
	multimesh_instance.multimesh = multimesh
	add_child(multimesh_instance)

func _build_outer_flat_frame() -> void:
	var outer_half: Vector2 = plane_size * 0.5
	var inner_half: Vector2 = relief_extent * 0.5
	if outer_half.x <= inner_half.x or outer_half.y <= inner_half.y:
		return # plane_size doesn't extend past relief_extent - nothing to frame

	var strip_y: float = -OUTER_FRAME_THICKNESS * 0.5
	var strips: Array[Dictionary] = [
		{
			"name": "North",
			"size": Vector3(plane_size.x, OUTER_FRAME_THICKNESS, outer_half.y - inner_half.y),
			"position": Vector3(0.0, strip_y, (inner_half.y + outer_half.y) * 0.5),
		},
		{
			"name": "South",
			"size": Vector3(plane_size.x, OUTER_FRAME_THICKNESS, outer_half.y - inner_half.y),
			"position": Vector3(0.0, strip_y, -(inner_half.y + outer_half.y) * 0.5),
		},
		{
			"name": "East",
			"size": Vector3(outer_half.x - inner_half.x, OUTER_FRAME_THICKNESS, relief_extent.y),
			"position": Vector3((inner_half.x + outer_half.x) * 0.5, strip_y, 0.0),
		},
		{
			"name": "West",
			"size": Vector3(outer_half.x - inner_half.x, OUTER_FRAME_THICKNESS, relief_extent.y),
			"position": Vector3(-(inner_half.x + outer_half.x) * 0.5, strip_y, 0.0),
		},
	]

	for strip: Dictionary in strips:
		var shape := BoxShape3D.new()
		shape.size = strip["size"]
		var shape_node := CollisionShape3D.new()
		shape_node.name = OUTER_FRAME_NODE_PREFIX + str(strip["name"])
		shape_node.shape = shape
		shape_node.position = strip["position"]
		add_child(shape_node)

# The coarse dressing mesh used to be one PlaneMesh spanning all of
# plane_size, fully underlying relief_extent's whole footprint at a flat
# y=0. That silently occluded every negative (wetness-sunk) dip in the
# relief mesh - the flat surface sat ABOVE the true dipped height and won
# the depth test there, so the visible surface in sunk areas was the flat
# plane, not the dip. That's what made draw_ground_debug's spheres (placed
# at the true, correct sunk height) look "buried" - not a coordinate bug,
# an occlusion bug. Fixed the same way the collision frame already is:
# four flat PlaneMesh strips tiling plane_size minus relief_extent, with
# no coverage inside it at all - reuses mesh_instance (the pre-existing
# node from the .tscn) as the North strip rather than leaving it orphaned.
func _rebuild_dressing_frame() -> void:
	_clear_dressing_frame_extras()
	_build_dressing_frame()

func _clear_dressing_frame_extras() -> void:
	for child in get_children():
		if String(child.name).begins_with(DRESSING_FRAME_NODE_PREFIX):
			child.queue_free()

func _build_dressing_frame() -> void:
	var outer_half: Vector2 = plane_size * 0.5
	var inner_half: Vector2 = relief_extent * 0.5
	if outer_half.x <= inner_half.x or outer_half.y <= inner_half.y:
		mesh_instance.mesh = null # plane_size doesn't extend past relief_extent - nothing to dress
		return

	mesh_instance.position = Vector3(0.0, 0.0, (inner_half.y + outer_half.y) * 0.5)
	mesh_instance.mesh = _build_dressing_plane(Vector2(plane_size.x, outer_half.y - inner_half.y))

	var strips: Array[Dictionary] = [
		{
			"name": "South",
			"size": Vector2(plane_size.x, outer_half.y - inner_half.y),
			"position": Vector3(0.0, 0.0, -(inner_half.y + outer_half.y) * 0.5),
		},
		{
			"name": "East",
			"size": Vector2(outer_half.x - inner_half.x, relief_extent.y),
			"position": Vector3((inner_half.x + outer_half.x) * 0.5, 0.0, 0.0),
		},
		{
			"name": "West",
			"size": Vector2(outer_half.x - inner_half.x, relief_extent.y),
			"position": Vector3(-(inner_half.x + outer_half.x) * 0.5, 0.0, 0.0),
		},
	]

	for strip: Dictionary in strips:
		var strip_instance := MeshInstance3D.new()
		strip_instance.name = DRESSING_FRAME_NODE_PREFIX + str(strip["name"])
		strip_instance.mesh = _build_dressing_plane(strip["size"])
		strip_instance.position = strip["position"]
		add_child(strip_instance)

func _build_dressing_plane(size: Vector2) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = dressing_subdivisions.x
	plane.subdivide_depth = dressing_subdivisions.y
	plane.material = _material
	return plane
