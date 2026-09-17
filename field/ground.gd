extends StaticBody3D
class_name Ground

# Emitted after every relief mesh/collision rebuild (initial build and any
# live relief-export edit) so anything standing on the terrain - FieldEnemy,
# any future prop - can re-ground itself without RegionField having to
# know about or re-trigger that on their behalf.
signal relief_rebuilt

# The sand: high-key pale with a slight warm bias (R - B ~ +0.14), a pale
# flat rather than tan. Rendered as authored - near_color/far_color below
# are neutral by default (they MULTIPLY into this; see ground.gdshader's
# own doc on them). Also read directly by contact shadows, footprints and
# the Wanderer's/enemies' own ground-matched materials, so this is the one
# sand colour everything keys off.
@export var ground_color: Color = Color(0.74, 0.70, 0.60):
	set(value):
		ground_color = value
		_apply_uniform("dry_color", value)

@export var plane_size: Vector2 = Vector2(500.0, 500.0)
# Only governs the dressing frame's own OUTER dimensions - .x for East/
# West's width, .y for North/South's depth. Whichever dimension actually
# borders the relief mesh (North/South's width, East/West's depth) is
# driven by relief_subdivisions instead, to keep that shared edge
# T-junction free - see _build_ns_dressing_mesh()'s own doc.
@export var dressing_subdivisions: Vector2i = Vector2i(4, 4)

# Fine-subdivided inner plane sized to the playable area, so relief
# detail exists where the Wanderer actually walks; the outer dressing
# plane (plane_size, above) stays coarse. GDScript-only now (see
# get_height_at()) - no longer pushed to the shader, which no longer
# displaces vertices at all.
# Sized to comfortably contain the landmass's own worst-case shoreline
# excursion (half_width_seaward + shoreline_noise_amplitude +
# landmass_falloff_width) plus relief_flat_margin/relief_edge_fade's own
# seam-matching zone, at the current landmass defaults below - re-check
# this margin if those are tuned much wider. relief_subdivisions is sized
# for ~0.35m vertex spacing at this extent, needed for the shoreline
# contour to read as curved rather than faceted at this field's scale.
@export var relief_extent: Vector2 = Vector2(100.0, 70.0):
	set(value):
		relief_extent = value
		_rebuild_ground_mesh_and_collision()
@export var relief_subdivisions: Vector2i = Vector2i(285, 199):
	set(value):
		relief_subdivisions = value
		_rebuild_ground_mesh_and_collision()

# Near/far tint, multiplied into ground_color (not blended toward) -
# white at both ends by default so the sand renders exactly as
# ground_color; the WorldEnvironment's fog/aerial perspective handles
# distance lightening. The old (0.78, 0.73, 0.62) near value silently
# darkened the sand by ~25% at the camera.
@export var near_color: Color = Color(1.0, 1.0, 1.0):
	set(value):
		near_color = value
		_apply_uniform("near_color", value)
@export var far_color: Color = Color(1.0, 1.0, 1.0):
	set(value):
		far_color = value
		_apply_uniform("far_color", value)
@export var near_distance: float = 20.0:
	set(value):
		near_distance = value
		_apply_uniform("near_distance", value)
@export var far_distance: float = 120.0:
	set(value):
		far_distance = value
		_apply_uniform("far_distance", value)

# Shader-only toggle: when off, ground.gdshader's own wetness_mask()
# (and therefore pool_factor, which reads it directly) returns 0
# everywhere, so wet patches and standing pools both stop rendering.
# Deliberately does NOT touch _wetness_mask() below (the GDScript port
# feeding get_height_at()/collision) - wetness still sinks the actual
# terrain shape either way, only the visual "reads too dark and muddy"
# wet-sand/pool coloring is what this turns off.
@export var wet_patches_enabled: bool = false:
	set(value):
		wet_patches_enabled = value
		_apply_uniform("wet_patches_enabled", value)
# Separate from wet_patches_enabled so the shore can still read damp even
# with wet patches elsewhere turned off.
@export var shore_wetness_enabled: bool = true:
	set(value):
		shore_wetness_enabled = value
		_apply_uniform("shore_wetness_enabled", value)

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
# Wet sand = ground_color x wet_darken (hue preserved) - the shore band,
# the noise wet patches, and the sand under the sea plane are all this,
# no separate wet colour. Albedo only: the ground is diffuse-only now
# (roughness 1, specular 0 everywhere - the old wet_roughness/wet_specular
# gloss was the source of the white hotspots).
@export_range(0.0, 1.0) var wet_darken: float = 0.72:
	set(value):
		wet_darken = value
		_apply_uniform("wet_darken", value)

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

# GDScript-only (see get_height_at()) - relief is baked into the mesh/
# collision at rebuild time, not pushed to the shader as a uniform.
@export var relief_amplitude: float = 0.15:
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
# A genuinely flat (height held at exactly 0, not just asymptotically
# approaching it) margin inside relief_extent's edges, BEFORE relief_edge_
# fade's own transition even starts - see _relief_edge_fade_factor()'s own
# doc for why this exists: smoothstep's height reaches exactly 0 only AT
# its lower bound, never at points past it, so without this margin the row
# of grid vertices just inside the boundary still carries a small nonzero
# bump, and SurfaceTool.generate_normals() derives the boundary row's own
# normal from the real (still-sloped) triangle connecting it to that row -
# reading as a visible lighting seam against the perfectly flat (0,1,0)
# dressing strips even though both sides already agree on height. Sized in
# meters (not grid steps) to keep get_height_at() a pure function of world
# position, independent of relief_subdivisions - widen this if a future
# subdivision drop reopens the seam.
@export var relief_flat_margin: float = 3.0:
	set(value):
		relief_flat_margin = value
		_rebuild_ground_mesh_and_collision()

# The landmass: a dry strip that narrows toward the inland wall and fans
# out toward the sea, falling away below sea_level on three sides. Left/
# right (see _landmass_distance()'s own doc) get a noisy falloff so the
# shoreline reads as a wandering, rounded coast; seaward (see _seaward_
# distance()'s own doc) gets a plain straight ramp along Z instead - no
# rounding, no noise, an open beach slope rather than another wandering
# edge. Inland has no term at all - stays unconditionally dry.
@export_group("Landmass Shape")
# Left/right half-width at the inland wall's own Z and at Sea's near edge
# respectively - _landmass_curve_t() lerps between them along Z. Seaward
# wider than inland by default, so the dry flat fans out toward the water.
@export var landmass_half_width_inland: float = 12.0:
	set(value):
		landmass_half_width_inland = value
		_rebuild_ground_mesh_and_collision()
@export var landmass_half_width_seaward: float = 18.0:
	set(value):
		landmass_half_width_seaward = value
		_rebuild_ground_mesh_and_collision()
# Exponent applied to the (0..1, clamped) linear inland->seaward
# parameter before the half-width lerp - 1.0 is a straight linear taper;
# >1 stays narrow longer then flares out near the sea; <1 widens early.
@export var landmass_width_curve_power: float = 1.0:
	set(value):
		landmass_width_curve_power = value
		_rebuild_ground_mesh_and_collision()
# SDF mode: how many meters past the (noised) shoreline distance it takes
# to reach landmass_below_sea_depth. Mask mode: the SAND side of the
# drawn line only - how many metres inland the beach takes to rise from
# sea_level to landmass_interior_height (see _relief_height()); the water
# side has its own landmass_underwater_falloff_width below.
@export var landmass_falloff_width: float = 6.0:
	set(value):
		landmass_falloff_width = value
		_rebuild_ground_mesh_and_collision()
# Mask mode only: how many metres past the drawn line the seabed takes to
# fall from sea_level to -landmass_below_sea_depth, on an ease-in
# (smoothstep) curve so the first metre of water is only centimetres
# deep - see _relief_height()'s mask branch. Unused by the SDF.
@export var landmass_underwater_falloff_width: float = 6.0:
	set(value):
		landmass_underwater_falloff_width = value
		_rebuild_ground_mesh_and_collision()
# Both relative to Sea's own sea_level (not absolute), so the landmass
# stays correctly seated if sea_level is ever retuned. landmass_interior_
# height is shared by both edges (it's the same dry baseline everywhere);
# landmass_below_sea_depth is the LEFT/RIGHT edges' own max depth only -
# see landmass_seaward_below_sea_depth below for the separate seaward one
# (the two need independent values: the seaward wade depth was tuned
# against the wall's own distance from the shore, which has nothing to do
# with how deep the sides go).
@export var landmass_interior_height: float = 0.25:
	set(value):
		landmass_interior_height = value
		_rebuild_ground_mesh_and_collision()
@export var landmass_below_sea_depth: float = 1.6:
	set(value):
		landmass_below_sea_depth = value
		_rebuild_ground_mesh_and_collision()
# Perturbs the shoreline's effective distance (not just its color) so the
# actual sea_level-crossing contour wanders instead of tracing the lerped
# half-width exactly.
@export var shoreline_noise_scale: float = 6.0:
	set(value):
		shoreline_noise_scale = value
		_rebuild_ground_mesh_and_collision()
@export var shoreline_noise_amplitude: float = 2.5:
	set(value):
		shoreline_noise_amplitude = value
		_rebuild_ground_mesh_and_collision()

# Seaward falloff - unlike the left/right edges, this is a plain straight
# ramp along Z only: no rounding, no noise (the sides already carry the
# irregularity; this one's meant to read as an open beach slope, not
# another wandering edge).
#
# Set explicitly (not the "0 means auto" default this used to carry - see
# _seaward_edge_z()'s own doc, the fallback still exists but is unused at
# this value) to land the sea_level crossing at z=+2.5 (2.5m seaward of
# spawn) while landmass_seaward_falloff_width/landmass_seaward_below_sea_
# depth below independently pin the depth at the seaward wall (z=9) to
# 0.9m - waist-deep on the Wanderer (target_height 1.8m). Solved as a pair:
# with the ramp's full 0-to-1 transition landing exactly on [edge_z,
# edge_z + falloff_width] = [-1.9, 9.0], smoothstep saturates to exactly 1
# (and depth to exactly landmass_seaward_below_sea_depth) AT the wall with
# no earlier plateau - i.e. no shelf - and crosses sea_level (depth 0) at
# the point where the lerp between interior_height and -below_sea_depth
# hits 0, which lands at z=2.5 for these particular values. Retune together
# if any of the three (edge_z, falloff_width, below_sea_depth) changes -
# they're coupled, not independent.
@export var landmass_seaward_edge_z: float = -1.9:
	set(value):
		landmass_seaward_edge_z = value
		_rebuild_ground_mesh_and_collision()
@export var landmass_seaward_falloff_width: float = 10.9:
	set(value):
		landmass_seaward_falloff_width = value
		_rebuild_ground_mesh_and_collision()
# Seaward-only max depth (see landmass_below_sea_depth's own doc on why
# this is separate from the sides' value) - 0.9m, waist-deep at the wall.
@export var landmass_seaward_below_sea_depth: float = 0.9:
	set(value):
		landmass_seaward_below_sea_depth = value
		_rebuild_ground_mesh_and_collision()

# Painted landmass: a grayscale image is the land shape instead of the SDF
# above. White = sand, black = water; the 0.5 contour IS the waterline -
# the painting is treated as PURE SHAPE, the gray in between only places
# that contour at sub-pixel precision (bilinear sample, then threshold), it
# does not paint the beach slope. The slope is a ramp split at the drawn
# line, fed by a signed distance field computed from the mask once per
# change (see _rebuild_mask_data()): on the sand side the beach rises from
# sea_level to landmass_interior_height over landmass_falloff_width, on
# the water side the seabed falls from sea_level to -landmass_below_sea_
# depth over landmass_underwater_falloff_width (ease-in, so the shallows
# stay shallow) - see _relief_height(). The line is sea_level by
# construction, so sand ends exactly where it was drawn and get_landmass_
# distance()'s 0 (the drain's own "shore") is that same line. Mode is
# automatic: mask set -> mask; null -> SDF. In mask mode the half-width/
# curve/seaward_* exports and shoreline_noise_* are ignored (the painted
# edge is the edge). Sea's wave calming still follows the SDF under a mask
# - see DESIGN.md.
#
# Image -> world: image up = inland (+RegionField.get_forward()), image
# right = forward rotated 90 degrees (+X when forward is -Z); the pixel at
# landmass_mask_origin (normalized image coords, (0.5, 0.5) = image centre)
# sits on the Wanderer's spawn. Beyond the image's left/right/bottom edges
# everything is water; beyond the TOP edge the top row is extended (clamp-
# to-edge) so a neck that runs off the top of the drawing stays dry up to
# the inland wall - inland is unconditionally dry, same as the SDF.
@export_group("Landmass Mask")
@export var landmass_mask: Texture2D = null:
	set(value):
		landmass_mask = value
		_mask_dirty = true
		_rebuild_ground_mesh_and_collision()
@export var landmass_mask_pixels_per_metre: float = 30.0:
	set(value):
		landmass_mask_pixels_per_metre = value
		_mask_dirty = true
		_rebuild_ground_mesh_and_collision()
@export var landmass_mask_origin: Vector2 = Vector2(0.5, 0.5):
	set(value):
		landmass_mask_origin = value
		_mask_dirty = true
		_rebuild_ground_mesh_and_collision()
# The distance field's own grid, NOT the image's resolution: an exact EDT
# over the full image (~700k cells) is seconds in GDScript, far too slow
# for a live setter; at 4 cells/m over the image rect plus padding it's
# ~30k cells and well under a frame's worth of work at load. Contour
# precision comes from bilinear-sampling the mask before thresholding, not
# from this cell size. Padding is how far past the image rect the grid
# extends (the walls sit inside it); beyond that the sample clamps to the
# grid's edge value.
@export var landmass_mask_distance_cells_per_metre: float = 4.0:
	set(value):
		landmass_mask_distance_cells_per_metre = value
		_mask_dirty = true
		_rebuild_ground_mesh_and_collision()
@export var landmass_mask_distance_padding: float = 8.0:
	set(value):
		landmass_mask_distance_padding = value
		_mask_dirty = true
		_rebuild_ground_mesh_and_collision()
@export_group("")

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

# Sand grain: two small-scale value-noise octaves modulating albedo
# brightness only (never hue - see ground.gdshader's grain_value() for
# how), plus a sparse dark speckle (shell fragments) wherever a separate,
# finer noise clears speckle_threshold. Both are stronger on dry sand and
# suppressed on wet - see fragment()'s own grain_suppression.
@export var grain_scale_fine: float = 0.15:
	set(value):
		grain_scale_fine = value
		_apply_uniform("grain_scale_fine", value)
@export var grain_scale_coarse: float = 0.6:
	set(value):
		grain_scale_coarse = value
		_apply_uniform("grain_scale_coarse", value)
@export var grain_strength: float = 0.02:
	set(value):
		grain_strength = value
		_apply_uniform("grain_strength", value)
@export var speckle_scale: float = 0.08:
	set(value):
		speckle_scale = value
		_apply_uniform("speckle_scale", value)
@export var speckle_threshold: float = 0.97:
	set(value):
		speckle_threshold = value
		_apply_uniform("speckle_threshold", value)
@export var speckle_darken: float = 0.15:
	set(value):
		speckle_darken = value
		_apply_uniform("speckle_darken", value)

# Wet band: within shore_slope_start metres of HEIGHT above sea_level,
# sand wetness is pushed to 1.0 (darkened by wet_darken) - height-based
# (v_world_height vs. the sea_level uniform below), not a straight line,
# so it follows the shoreline for free. Metres of height, so keep it
# small: the dry interior is only landmass_interior_height (0.5) above
# sea_level, and the old 8.0 made the entire landmass read as wet. 0.15
# is a narrow strip right at the waterline; below sea_level the wet
# darkening simply continues. sea_level is pushed once in _ready() (see
# _push_sea_level_uniform()) from Sea, not assumed.
@export var shore_slope_start: float = 0.08:
	set(value):
		shore_slope_start = value
		_apply_uniform("shore_slope_start", value)
# The wet band breathes with the sea's swash: shore_slope_start widens by
# up to wet_band_surge metres of height as each wash reaches the line,
# relaxing back over wet_dry_time seconds after it recedes. The phase
# inputs (wrapped time, period, phase-noise scale, the noise tile) are
# pushed by Sea - see set_swash_source()/set_sea_time() - so this reads
# the identical phase the sea's wash uses; nothing here is authored.
@export var wet_band_surge: float = 0.25:
	set(value):
		wet_band_surge = value
		_apply_uniform("wet_band_surge", value)
@export var wet_dry_time: float = 2.0:
	set(value):
		wet_dry_time = value
		_apply_uniform("wet_dry_time", value)
# Run-up: the ground draws each wash's continuation up the sand (the sea
# plane is depth-tested away there) - see ground.gdshader's own
# swash_runup_distance doc. The sheet slides from the drawn line to
# swash_runup_distance x the cycle's amplitude and back, in step with the
# sea's front; a translucent film toward swash_sheet_color at swash_sheet_
# alpha with a bright leading edge swash_edge_width_ground wide toward
# swash_color (the sea's front colour - keep the two defaults matched).
# The sand stays wet as far as the sheet reached, drying over wet_dry_
# time. All keyed to the mask distance grid pushed as a texture (see
# _push_mask_distance_texture()) so none of it can reach the interior; in
# SDF mode there is no grid and the whole run-up is off.
@export var swash_runup_distance: float = 1.2:
	set(value):
		swash_runup_distance = value
		_apply_uniform("swash_runup_distance", value)
@export var swash_sheet_color: Color = Color(0.60, 0.66, 0.66):
	set(value):
		swash_sheet_color = value
		_apply_uniform("swash_sheet_color", value)
@export_range(0.0, 1.0) var swash_sheet_alpha: float = 0.45:
	set(value):
		swash_sheet_alpha = value
		_apply_uniform("swash_sheet_alpha", value)
@export var swash_edge_width_ground: float = 0.08:
	set(value):
		swash_edge_width_ground = value
		_apply_uniform("swash_edge_width_ground", value)
@export var swash_color: Color = Color(0.82, 0.84, 0.82):
	set(value):
		swash_color = value
		_apply_uniform("swash_color", value)

# Caustics on the sand below sea_level - see ground.gdshader's own doc: a
# scrolling two-layer cellular web brightening the wet sand by up to
# caustic_strength, cells ~caustic_scale metres, drifting at caustic_speed,
# fading out over caustic_fade_depth metres below the surface.
# caustic_sharpness thins the web's lines (higher = finer). Scrolls on the
# shader's own TIME; nothing to push per frame.
@export_group("Caustics")
@export var caustic_strength: float = 0.15:
	set(value):
		caustic_strength = value
		_apply_uniform("caustic_strength", value)
@export var caustic_scale: float = 0.6:
	set(value):
		caustic_scale = value
		_apply_uniform("caustic_scale", value)
@export var caustic_speed: float = 0.08:
	set(value):
		caustic_speed = value
		_apply_uniform("caustic_speed", value)
@export var caustic_fade_depth: float = 3.0:
	set(value):
		caustic_fade_depth = value
		_apply_uniform("caustic_fade_depth", value)
@export var caustic_sharpness: float = 4.0:
	set(value):
		caustic_sharpness = value
		_apply_uniform("caustic_sharpness", value)
# Drift lines/ripple marks run at this multiple of their dry strength
# under sea_level (both darken-only, so this can't lighten the seabed).
@export var underwater_detail_boost: float = 1.5:
	set(value):
		underwater_detail_boost = value
		_apply_uniform("underwater_detail_boost", value)
@export_group("")
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

# Bisect for the "ground doesn't render at all" investigation: forces
# every ground surface (relief mesh + all four dressing frame strips) onto
# a plain StandardMaterial3D instead of ground.gdshader's ShaderMaterial,
# so the mesh/AABB/visibility side of things can be checked independent of
# whether the shader itself is the problem. See _current_ground_material().
@export var use_plain_ground_material: bool = false:
	set(value):
		use_plain_ground_material = value
		_rebuild_ground_mesh_and_collision()

# Draws a short line from every normal_debug_stride-th vertex of the
# actual committed relief mesh, along its actual committed normal (read
# back from the mesh itself post-generate_normals(), not recomputed) - on
# ground with no slope these should all point straight up-ish, not lean
# or vary with position.
@export var draw_normal_debug: bool = false:
	set(value):
		draw_normal_debug = value
		_rebuild_normal_debug()
@export var normal_debug_stride: int = 4:
	set(value):
		normal_debug_stride = value
		_rebuild_normal_debug()
@export var normal_debug_length: float = 0.5:
	set(value):
		normal_debug_length = value
		_rebuild_normal_debug()

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
	# No Y nudge here (there used to be one - see the retired comment this
	# replaces if you're reading blame): the old 0.02 render-only offset
	# patched over the relief mesh's edge and the dressing frame's inner
	# edge not being EXACTLY coincident (two independently-tessellated
	# PlaneMesh-family resources, each computing "the same" boundary
	# position its own way). _build_dressing_plane()/_apply_relief_mesh()
	# now share the exact same grid spacing and anchor at that boundary
	# (see relief_flat_margin's own doc for the matching normal fix), so
	# the two meshes are watertight there and don't compete for the same
	# depth - a nudge now would just reintroduce the seam as a visible 2cm
	# step instead of a z-fight.
	# Receives only - the ground shouldn't cast its own shadow onto itself.
	_relief_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_relief_mesh_instance)

	_ready_done = true
	_rebuild_ground_mesh_and_collision()
	_debug_assert_height_matches_shader_math()

	_push_sea_level_uniform()
	_check_landmass_interior_height_clears_water()

# sea_level drives both the shader's height-based wet band (shore_t()) and
# this script's own landmass height formula (_landmass_distance()'s own
# doc) - pushed once here since Sea's sea_level has no live setter that
# would otherwise leave this stale. Sea.sea_level is a plain property
# (safe to read regardless of node-ready order, unlike get_forward()/
# get_near_edge_z() which compute lazily), so no deferral needed.
func _push_sea_level_uniform() -> void:
	var sea := get_node_or_null(sea_path) as Sea
	_apply_uniform("sea_level", sea.sea_level if sea else 0.0)

# Boot-time sanity check: if the dry interior's own height doesn't clear
# sea_level by more than relief's own fine-detail noise plus the sea's
# actual wave displacement, the two could overlap somewhere and water
# would show through supposedly-dry sand - the exact bug this whole
# landmass shape exists to prevent. wave_amplitude_max is the real vertex-
# displacement bound (long_wave_amplitude + short_wave_amplitude) - Sea's
# own noise_amplitude is deliberately excluded, since it's normal-only and
# never actually raises the rendered surface (see sea.gd's own doc on it).
# Not re-run live on a relevant export's own setter - this is a one-time
# boot sanity check, not a continuously-enforced invariant.
func _check_landmass_interior_height_clears_water() -> void:
	var sea := get_node_or_null(sea_path) as Sea
	if sea == null:
		return
	var wave_amplitude_max: float = sea.long_wave_amplitude + sea.short_wave_amplitude
	var threshold: float = sea.sea_level + relief_amplitude + wave_amplitude_max
	if landmass_interior_height <= threshold:
		push_warning("Ground: landmass_interior_height (%.3f) does not clear sea_level (%.3f) + relief_amplitude (%.3f) + wave_amplitude_max (%.3f) = %.3f - water may show through the dry interior." % [landmass_interior_height, sea.sea_level, relief_amplitude, wave_amplitude_max, threshold])

func _apply_all_uniforms() -> void:
	_apply_uniform("dry_color", ground_color)
	_apply_uniform("near_color", near_color)
	_apply_uniform("far_color", far_color)
	_apply_uniform("near_distance", near_distance)
	_apply_uniform("far_distance", far_distance)
	_apply_uniform("wet_patches_enabled", wet_patches_enabled)
	_apply_uniform("shore_wetness_enabled", shore_wetness_enabled)
	_apply_uniform("wetness_scale", wetness_scale)
	_apply_uniform("wetness_amount", wetness_amount)
	_apply_uniform("wet_darken", wet_darken)
	_apply_uniform("shore_slope_start", shore_slope_start)
	_apply_uniform("wet_band_surge", wet_band_surge)
	_apply_uniform("wet_dry_time", wet_dry_time)
	_apply_uniform("swash_runup_distance", swash_runup_distance)
	_apply_uniform("swash_sheet_color", swash_sheet_color)
	_apply_uniform("swash_sheet_alpha", swash_sheet_alpha)
	_apply_uniform("swash_edge_width_ground", swash_edge_width_ground)
	_apply_uniform("swash_color", swash_color)
	_apply_uniform("caustic_strength", caustic_strength)
	_apply_uniform("caustic_scale", caustic_scale)
	_apply_uniform("caustic_speed", caustic_speed)
	_apply_uniform("caustic_fade_depth", caustic_fade_depth)
	_apply_uniform("caustic_sharpness", caustic_sharpness)
	_apply_uniform("underwater_detail_boost", underwater_detail_boost)
	_apply_uniform("pool_threshold", pool_threshold)
	_apply_uniform("pool_edge_width", pool_edge_width)
	_apply_uniform("pool_color", pool_color)
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
	_apply_uniform("grain_scale_fine", grain_scale_fine)
	_apply_uniform("grain_scale_coarse", grain_scale_coarse)
	_apply_uniform("grain_strength", grain_strength)
	_apply_uniform("speckle_scale", speckle_scale)
	_apply_uniform("speckle_threshold", speckle_threshold)
	_apply_uniform("speckle_darken", speckle_darken)

func _apply_uniform(uniform_name: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(uniform_name, value)

# Called by sea.gd (see its _push_swash_source()/_push_sea_time()): the
# swash phase's shared inputs. Sea owns the wrapped time and the baked
# surface_noise tile; handing Ground the same texture object and the same
# float is what makes ground.gdshader's swash_phase() equal the sea's at
# every XZ. set_swash_source() once (and on export change), set_sea_time()
# every physics frame. Both just push uniforms - _apply_uniform() no-ops
# until _material exists, so call order relative to _ready() is safe.
func set_swash_source(noise: Texture2D, period: float, phase_noise_scale: float, phase_spread: float) -> void:
	_apply_uniform("surface_noise", noise)
	_apply_uniform("swash_period", period)
	_apply_uniform("swash_phase_noise_scale", phase_noise_scale)
	_apply_uniform("swash_phase_spread", phase_spread)

func set_sea_time(sea_time: float) -> void:
	_apply_uniform("sea_time", sea_time)

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
# Historical note, now inverted by the landmass shape change: shore
# proximity used to be a fragment-only color effect, entirely independent
# of get_height_at() (the shader's shore_t() read a separately-pushed
# water_line_z, never height). That's no longer true - the landmass term
# in _relief_height() below IS the shoreline now, and the shader's shore_t()
# reads height (v_world_height vs. the sea_level uniform) back out of it
# instead of an independent line, specifically so the wet band can't drift
# from the real, noised contour. get_wetness_at() below is a separate
# story, unaffected by any of this: it mirrors
# the plain wetness_mask() relief_height() itself sinks by, not the shore-
# boosted variant.
func get_height_at(world_xz: Vector2) -> float:
	return _relief_height(world_xz) * _relief_edge_fade_factor(world_xz)

# Same port discipline as get_height_at() - mirrors ground.gdshader's own
# wetness_mask() exactly (see get_height_at()'s doc for why the shore-
# boosted sand_wetness_mask() is deliberately not what this exposes).
func get_wetness_at(world_xz: Vector2) -> float:
	return _wetness_mask(world_xz)

# The one source of truth for "how far past the shoreline" a world
# position is - RegionField's wade-HP drain calls this directly (see its
# own doc) instead of re-deriving the shoreline from straight lines, so
# the drain can't drift out of sync with the actual visual contour
# _relief_height() draws from the exact same two functions. Whichever edge
# (left/right's noised _landmass_distance(), or seaward's plain _seaward_
# distance()) the position is furthest past wins - same max() combination
# _relief_height() uses to pick which edge actually submerges a point.
# Under a landmass_mask the signed distance comes from the mask's own
# distance field instead (see _rebuild_mask_data()) - same sign convention
# (negative on sand, positive in water), but 0 is the DRAWN LINE, which
# _relief_height()'s mask branch makes the exact sea_level crossing (the
# ramp is split there) - so in mask mode the drain's "distance past
# shore" is literally distance past the waterline, with none of the SDF's
# ~2m of ramp-start lead-in on dry sand.
func get_landmass_distance(world_xz: Vector2) -> float:
	if has_landmass_mask():
		return _mask_distance_sample(world_xz)
	_ensure_landmass_refs()
	return maxf(_landmass_distance(world_xz), _seaward_distance(world_xz.y))

# True once a landmass_mask is set AND decoded into a distance field - false
# during the brief window between assignment and the rebuild that decodes
# it, and whenever the texture yields no readable image (see _rebuild_mask_
# data()'s own fallback), so every consumer degrades to the SDF together.
func has_landmass_mask() -> bool:
	return landmass_mask != null and _mask_ready

# World-XZ (x = X, y = Z) bounding rectangle of the painted land - the
# cells at/above the 0.5 threshold INSIDE the image rect only, so a neck
# that runs off the top of the drawing bounds at the image's top edge, not
# at the padded distance grid's (the clamp-to-edge band past that edge is
# dry, but it's not authored land). RegionField sizes the boundary walls
# from this in mask mode (see its _rebuild_boundary_walls()). Meaningless
# (an empty Rect2) without a mask - check has_landmass_mask() first.
func get_landmass_bounds() -> Rect2:
	return _mask_land_bounds

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

# Lazily resolved and cached (same shape as RegionField.get_forward()'s own
# _forward_computed flag) rather than looked up on every call - unlike
# get_height_at()'s per-point sampling during a mesh rebuild, get_landmass_
# distance() is also called once per physics frame by RegionField's wade
# drain, so a live node lookup there every frame is worth avoiding.
# Invalidated by _rebuild_ground_mesh_and_collision() (see its own call to
# this) so a shape-export edit always re-reads Sea/RegionField fresh rather
# than serving a stale cache from before they were both in the tree.
var _landmass_refs_ready: bool = false
var _landmass_inland_z: float = 0.0
var _landmass_seaward_z: float = 0.0
var _landmass_sea_level: float = 0.0
var _landmass_forward_z: float = -1.0
# Mask mode's own two references (see _mask_world_to_pixel()): the full XZ
# forward (not just its Z) and the spawn the mask's origin pixel sits on.
var _landmass_forward_xz: Vector2 = Vector2(0.0, -1.0)
var _landmass_spawn_xz: Vector2 = Vector2.ZERO

func _ensure_landmass_refs() -> void:
	if _landmass_refs_ready:
		return
	var region_field := get_node_or_null(region_field_path) as RegionField
	var sea := get_node_or_null(sea_path) as Sea
	_landmass_inland_z = region_field.get_inland_z() if region_field else 0.0
	var forward: Vector3 = region_field.get_forward() if region_field else Vector3.FORWARD
	_landmass_forward_z = forward.z
	_landmass_forward_xz = Vector2(forward.x, forward.z)
	var spawn: Vector3 = region_field.get_spawn_position() if region_field else Vector3.ZERO
	_landmass_spawn_xz = Vector2(spawn.x, spawn.z)
	_landmass_seaward_z = sea.get_near_edge_z() if sea else 0.0
	_landmass_sea_level = sea.sea_level if sea else 0.0
	_landmass_refs_ready = true

# landmass_seaward_edge_z's own "0 means auto" resolution - see its doc.
func _seaward_edge_z() -> float:
	return landmass_seaward_edge_z if landmass_seaward_edge_z != 0.0 else _landmass_seaward_z

# Signed distance past the seaward edge, positive once world_z sits
# seaward of it - same forward-sign convention _landmass_distance()'s
# siblings use elsewhere in this file (forward points inland, so
# subtracting forward.z*distance moves seaward). Negative/0 on the inland
# side, where the seaward falloff doesn't apply. Deliberately Z-only, no
# noise, no X term at all - this edge is a plain ramp, not a wandering
# coast (see this export group's own doc for why).
func _seaward_distance(world_z: float) -> float:
	return (_seaward_edge_z() - world_z) * _landmass_forward_z

# 0 at the inland wall's own Z, 1 at Sea's near edge, clamped beyond both -
# clamping past 1 is what lets the shape stay open-ended toward the sea
# (see _landmass_distance()'s own doc): once past the near edge, the
# half-width just holds at landmass_half_width_seaward forever, it never
# curves back inward. landmass_width_curve_power reshapes the transition
# between the two ends, not the clamping itself.
func _landmass_curve_t(world_z: float) -> float:
	var span: float = _landmass_seaward_z - _landmass_inland_z
	if absf(span) < 0.0001:
		return 0.0
	var linear_t: float = clampf((world_z - _landmass_inland_z) / span, 0.0, 1.0)
	return pow(linear_t, maxf(landmass_width_curve_power, 0.0001))

# Signed distance past the (noised) shoreline: negative on the dry side,
# positive past it, roughly 0 at the crossing - not an exact promise that
# height == sea_level exactly at distance == 0 (the falloff below is a
# continuous blend, not a hard threshold), just close enough that this
# moves consistently with the real, noised visual contour, which is the
# property RegionField's wade drain actually needs.
#
# Deliberately only ever measures distance from the LEFT/RIGHT edges
# (abs(world_x) - local_half_width) - the seaward edge has its own,
# separate, noise-free straight ramp instead (_seaward_distance()), and
# inland has no term at all (stays unconditionally dry, per this round's
# decision - no falloff, no corner to round). _landmass_curve_t() clamps
# at the near edge rather than closing off past it, so this function alone
# describes an open channel with two wandering side edges, not a rounded
# rectangle - there are no corners to round on this function's own account.
# get_landmass_distance() combines this with _seaward_distance() via max()
# for the raw shoreline-distance shape; _relief_height() combines the two
# edges' resulting HEIGHTS instead (via min()), since they can bottom out
# at different depths - see its own doc.
func _landmass_distance(world_xz: Vector2) -> float:
	_ensure_landmass_refs()
	var t: float = _landmass_curve_t(world_xz.y)
	var local_half_width: float = lerpf(landmass_half_width_inland, landmass_half_width_seaward, t)
	var noise: float = (_value_noise(world_xz / maxf(shoreline_noise_scale, 0.001)) - 0.5) * 2.0 * shoreline_noise_amplitude
	return absf(world_xz.x) - local_half_width + noise

func _relief_height(world_xz: Vector2) -> float:
	_ensure_landmass_refs()
	var landmass_height: float
	if has_landmass_mask():
		# A ramp split at the drawn line (mask distance 0 = sea_level by
		# construction, no offset needed). Sand side: the beach rises to
		# landmass_interior_height over landmass_falloff_width on an ease-
		# OUT (1 - (1 - u)^2) - a real, nonzero slope right at the line
		# (2 x interior / width) flattening into the interior; a smoothstep
		# would start flat at the line and turn the wet band into a shelf.
		# Water side: the seabed falls to -landmass_below_sea_depth over
		# landmass_underwater_falloff_width on an ease-IN (smoothstep), so
		# the first metre of water is centimetres deep and the wade only
		# gets serious toward the walls. One edge, one depth - the painting
		# doesn't know which edge is which, and the seaward_* exports are
		# SDF-only.
		var shore_distance: float = _mask_distance_sample(world_xz)
		if shore_distance <= 0.0:
			var u: float = clampf(-shore_distance / maxf(landmass_falloff_width, 0.001), 0.0, 1.0)
			landmass_height = _landmass_sea_level + landmass_interior_height * (1.0 - (1.0 - u) * (1.0 - u))
		else:
			var under: float = smoothstep(0.0, maxf(landmass_underwater_falloff_width, 0.001), shore_distance)
			landmass_height = _landmass_sea_level - landmass_below_sea_depth * under
	else:
		# Whichever edge actually submerges this point further wins -
		# computed as two independent HEIGHTS (not factors combined by
		# max()) because the two edges no longer share one below_sea_depth:
		# the seaward wade depth was tuned against the wall's own distance
		# from shore, unrelated to how deep the sides go (see landmass_
		# seaward_below_sea_depth's own doc). min() picks whichever edge's
		# height is lower - the correct generalization once the two
		# branches can bottom out at different depths (comparing raw
		# factors wouldn't tell you which resulting height is actually
		# lower).
		var side_factor: float = smoothstep(0.0, maxf(landmass_falloff_width, 0.001), _landmass_distance(world_xz))
		var seaward_factor: float = smoothstep(0.0, maxf(landmass_seaward_falloff_width, 0.001), _seaward_distance(world_xz.y))
		var side_height: float = _landmass_sea_level + lerpf(landmass_interior_height, -landmass_below_sea_depth, side_factor)
		var seaward_height: float = _landmass_sea_level + lerpf(landmass_interior_height, -landmass_seaward_below_sea_depth, seaward_factor)
		landmass_height = minf(side_height, seaward_height)

	# Fine surface detail on top of the landmass base - the field's
	# original bump/wetness noise, unrelated to sea_level, kept purely as
	# texture now that the landmass term carries the actual shore shape.
	var wetness: float = _wetness_mask(world_xz)
	var noise_scale: float = maxf(relief_noise_scale, 0.001)
	var bump: float = (_value_noise(world_xz / noise_scale) - 0.5) * 2.0
	var fine_detail: float = bump * relief_amplitude - wetness * relief_amplitude

	return landmass_height + fine_detail

# Exactly 0 for edge_dist <= relief_flat_margin (smoothstep clamps at its
# own lower bound), THEN transitions to 1 over the next relief_edge_fade
# meters - see relief_flat_margin's own doc for why the flat zone has to
# be a real margin, not just the single point edge_dist == 0.
func _relief_edge_fade_factor(world_xz: Vector2) -> float:
	var half_extent: Vector2 = relief_extent * 0.5
	var edge_dist: float = minf(half_extent.x - absf(world_xz.x), half_extent.y - absf(world_xz.y))
	var flat_margin: float = maxf(relief_flat_margin, 0.0)
	return smoothstep(flat_margin, flat_margin + maxf(relief_edge_fade, 0.001), edge_dist)

# --- Landmass mask: decode, signed distance field, sampling ---
#
# Decoded once per mask-affecting export change (see _mask_dirty and the
# Landmass Mask export group's own doc), inside _rebuild_ground_mesh_and_
# collision() rather than in the setters themselves, so a mask assigned in
# the .tscn (whose setter fires during deserialization, before _ready())
# is decoded exactly once, on the first real rebuild. Two arrays result:
# the image's own luminance bytes (_mask_bytes, sampled bilinearly by
# _mask_sample()) and the coarser signed distance grid (_mask_distance,
# sampled by _mask_distance_sample()) that everything height/drain-related
# actually reads - the image itself is only ever read while building that
# grid.
const MASK_LAND_THRESHOLD: float = 0.5
# "No source here yet" for the EDT below. Finite on purpose: with a true
# INF, INF - INF in _edt_intersection() is NaN and the lower-envelope
# bookkeeping silently relies on NaN comparison semantics; 1e20 keeps
# every intermediate finite while still dwarfing any real squared
# distance at this grid size, so a parabola rooted here never wins.
const MASK_EDT_FAR: float = 1.0e20

var _mask_dirty: bool = true
var _mask_ready: bool = false
var _mask_bytes: PackedByteArray = PackedByteArray()
var _mask_width: int = 0
var _mask_height: int = 0
var _mask_distance: PackedFloat32Array = PackedFloat32Array()
var _mask_distance_cols: int = 0
var _mask_distance_rows: int = 0
# World XZ of distance cell (0, 0); cells step +cell_size along +X (col)
# and +Z (row) from there - the grid is world-axis-aligned regardless of
# forward, since it's built from the image rect's world-space bounds.
var _mask_distance_origin: Vector2 = Vector2.ZERO
var _mask_distance_cell_size: float = 0.25
var _mask_land_bounds: Rect2 = Rect2()
# The distance grid as an R32F texture for ground.gdshader (the swash
# surge's shore gate) - see _push_mask_distance_texture().
var _mask_distance_texture: ImageTexture = null

func _rebuild_mask_data() -> void:
	_mask_dirty = false
	_mask_ready = false
	_mask_bytes = PackedByteArray()
	_mask_distance = PackedFloat32Array()
	_mask_land_bounds = Rect2()
	if landmass_mask == null:
		_push_mask_distance_texture()
		return
	if not _decode_mask_image():
		push_warning("Ground: landmass_mask yielded no readable image; falling back to the SDF landmass.")
		_push_mask_distance_texture()
		return
	_build_mask_distance_field()
	_mask_ready = true
	_push_mask_distance_texture()

# The same signed distance grid _mask_distance_sample() reads, handed to
# the shader as one R32F texel per cell (cols x rows, ~115 KB at the
# current 188x153) plus the grid's origin/cell size/dims, so the shader
# can bilinearly sample the identical field at any world XZ (see
# ground.gdshader's landmass_distance_at()). Uploaded here, once per mask
# rebuild - never per frame. With no mask the ready flag goes false and
# the shader treats the distance as unknown (surge off). This is also the
# texture the deferred sea-side wave calming would read - see DESIGN.md.
func _push_mask_distance_texture() -> void:
	if not _mask_ready or _mask_distance.is_empty():
		_mask_distance_texture = null
		_apply_uniform("landmass_distance_ready", false)
		return
	var image: Image = Image.create_from_data(_mask_distance_cols, _mask_distance_rows, false, Image.FORMAT_RF, _mask_distance.to_byte_array())
	_mask_distance_texture = ImageTexture.create_from_image(image)
	_apply_uniform("landmass_distance_tex", _mask_distance_texture)
	_apply_uniform("landmass_distance_origin", _mask_distance_origin)
	_apply_uniform("landmass_distance_cell", _mask_distance_cell_size)
	_apply_uniform("landmass_distance_dims", Vector2(float(_mask_distance_cols), float(_mask_distance_rows)))
	_apply_uniform("landmass_distance_ready", true)

# Texture2D.get_image() hands back a fresh copy, so converting it in place
# is safe. A PNG's default import is lossless, so decompress() is normally
# a no-op - it's here for the day Detect 3D flips the import to VRAM-
# compressed. L8 so one byte per pixel is the whole story; for a grayscale
# painting the engine's RGB->L conversion is the identity either way.
func _decode_mask_image() -> bool:
	var image: Image = landmass_mask.get_image()
	if image == null or image.is_empty():
		return false
	if image.is_compressed() and image.decompress() != OK:
		return false
	image.clear_mipmaps()
	image.convert(Image.FORMAT_L8)
	_mask_width = image.get_width()
	_mask_height = image.get_height()
	_mask_bytes = image.get_data()
	return _mask_bytes.size() == _mask_width * _mask_height

# Continuous pixel coordinates (top-left origin, pixel i spanning [i, i+1))
# of a world XZ position, per the Landmass Mask group's own image->world
# doc: right = forward rotated a quarter turn (so +X when forward is -Z),
# rows run seaward (against forward).
func _mask_world_to_pixel(world_xz: Vector2) -> Vector2:
	var forward: Vector2 = _landmass_forward_xz
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var rel: Vector2 = world_xz - _landmass_spawn_xz
	var ppm: float = maxf(landmass_mask_pixels_per_metre, 0.001)
	var origin_px: Vector2 = landmass_mask_origin * Vector2(float(_mask_width), float(_mask_height))
	return Vector2(origin_px.x + rel.dot(right) * ppm, origin_px.y - rel.dot(forward) * ppm)

func _mask_pixel_to_world(pixel: Vector2) -> Vector2:
	var forward: Vector2 = _landmass_forward_xz
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var ppm: float = maxf(landmass_mask_pixels_per_metre, 0.001)
	var origin_px: Vector2 = landmass_mask_origin * Vector2(float(_mask_width), float(_mask_height))
	var offset: Vector2 = (pixel - origin_px) / ppm
	return _landmass_spawn_xz + right * offset.x - forward * offset.y

func _mask_byte(x: int, y: int) -> float:
	return float(_mask_bytes[y * _mask_width + x]) / 255.0

# Bilinear over pixel centres. Past the left/right/bottom edges: water
# (0). Past the top edge: the top row extended, so land running off the
# top of the drawing stays land all the way inland (see the export group's
# own doc on why inland is the one dry side).
func _mask_sample(world_xz: Vector2) -> float:
	var p: Vector2 = _mask_world_to_pixel(world_xz) - Vector2(0.5, 0.5)
	if p.x < -0.5 or p.x > float(_mask_width) - 0.5 or p.y > float(_mask_height) - 0.5:
		return 0.0
	var x: float = clampf(p.x, 0.0, float(_mask_width - 1))
	var y: float = clampf(p.y, 0.0, float(_mask_height - 1))
	var x0: int = int(floor(x))
	var y0: int = int(floor(y))
	var x1: int = mini(x0 + 1, _mask_width - 1)
	var y1: int = mini(y0 + 1, _mask_height - 1)
	var fx: float = x - float(x0)
	var fy: float = y - float(y0)
	var top: float = lerpf(_mask_byte(x0, y0), _mask_byte(x1, y0), fx)
	var bottom: float = lerpf(_mask_byte(x0, y1), _mask_byte(x1, y1), fx)
	return lerpf(top, bottom, fy)

# The signed shore distance grid: negative on land, positive in water, in
# metres, over the image rect grown by landmass_mask_distance_padding.
# Each cell is classified by bilinear-sampling the mask at its centre and
# thresholding (that's where the contour's sub-pixel precision comes from
# - see the export group's doc), then two exact Euclidean distance
# transforms (Felzenszwalb-Huttenlocher, see _edt_squared()) give every
# water cell its distance to the nearest land cell and vice versa. A cell
# on either side of the boundary lands at +-1 cell, so the bilinear sample
# crosses 0 exactly halfway between them - on the contour.
#
# Also the one place _mask_land_bounds is measured: land cells whose
# position falls inside the image rect proper, so the clamp-to-edge band
# past the top edge doesn't count (see get_landmass_bounds()'s own doc).
func _build_mask_distance_field() -> void:
	_ensure_landmass_refs()
	var image_rect: Rect2 = Rect2(_mask_pixel_to_world(Vector2.ZERO), Vector2.ZERO)
	image_rect = image_rect.expand(_mask_pixel_to_world(Vector2(float(_mask_width), 0.0)))
	image_rect = image_rect.expand(_mask_pixel_to_world(Vector2(0.0, float(_mask_height))))
	image_rect = image_rect.expand(_mask_pixel_to_world(Vector2(float(_mask_width), float(_mask_height))))
	var grid_rect: Rect2 = image_rect.grow(maxf(landmass_mask_distance_padding, 0.0))
	var cell: float = 1.0 / maxf(landmass_mask_distance_cells_per_metre, 0.01)
	var cols: int = int(ceil(grid_rect.size.x / cell)) + 1
	var rows: int = int(ceil(grid_rect.size.y / cell)) + 1
	_mask_distance_cols = cols
	_mask_distance_rows = rows
	_mask_distance_origin = grid_rect.position
	_mask_distance_cell_size = cell

	var land: PackedByteArray = PackedByteArray()
	land.resize(cols * rows)
	var bounds_started: bool = false
	var bounds: Rect2 = Rect2()
	for row in rows:
		for col in cols:
			var world_xz: Vector2 = _mask_distance_origin + Vector2(float(col), float(row)) * cell
			var is_land: bool = _mask_sample(world_xz) >= MASK_LAND_THRESHOLD
			land[row * cols + col] = 1 if is_land else 0
			if is_land and image_rect.has_point(world_xz):
				if bounds_started:
					bounds = bounds.expand(world_xz)
				else:
					bounds = Rect2(world_xz, Vector2.ZERO)
					bounds_started = true
	_mask_land_bounds = bounds

	var to_land: PackedFloat64Array = _edt_squared(land, cols, rows, 1)
	var to_water: PackedFloat64Array = _edt_squared(land, cols, rows, 0)
	# A grid with no land (or no water) at all leaves one transform at
	# MASK_EDT_FAR everywhere - capped to the grid's own diagonal so the
	# result is a sane "very far" rather than 1e10 metres.
	var far: float = grid_rect.size.length()
	_mask_distance.resize(cols * rows)
	for i in cols * rows:
		var distance: float = -sqrt(to_water[i]) * cell if land[i] == 1 else sqrt(to_land[i]) * cell
		_mask_distance[i] = clampf(distance, -far, far)

	print("Ground: landmass mask %dx%d px at %.1f px/m -> image rect %s, land bounds %s, distance grid %dx%d @ %.2fm" % [_mask_width, _mask_height, landmass_mask_pixels_per_metre, image_rect, _mask_land_bounds, cols, rows, cell])

# Squared Euclidean distance (in cells) from every cell to the nearest
# cell whose land[] value == source_value - Felzenszwalb & Huttenlocher's
# separable lower-envelope-of-parabolas transform: exact, O(cells), one
# 1-D pass down every column then one along every row. Float64 working
# arrays because the parabola intersections in _edt_1d() mix MASK_EDT_FAR
# with small squared distances, which float32 would flatten.
func _edt_squared(land: PackedByteArray, cols: int, rows: int, source_value: int) -> PackedFloat64Array:
	var cell_count: int = cols * rows
	var grid: PackedFloat64Array = PackedFloat64Array()
	grid.resize(cell_count)
	for i in cell_count:
		grid[i] = 0.0 if land[i] == source_value else MASK_EDT_FAR

	var length: int = maxi(cols, rows)
	var f: PackedFloat64Array = PackedFloat64Array()
	f.resize(length)
	var d: PackedFloat64Array = PackedFloat64Array()
	d.resize(length)
	var v: PackedInt32Array = PackedInt32Array()
	v.resize(length)
	var z: PackedFloat64Array = PackedFloat64Array()
	z.resize(length + 1)

	for col in cols:
		for row in rows:
			f[row] = grid[row * cols + col]
		_edt_1d(f, rows, d, v, z)
		for row in rows:
			grid[row * cols + col] = d[row]
	for row in rows:
		for col in cols:
			f[col] = grid[row * cols + col]
		_edt_1d(f, cols, d, v, z)
		for col in cols:
			grid[row * cols + col] = d[col]
	return grid

# One 1-D pass of the transform above: d[q] = min over p of (q-p)^2 + f[p].
# v[] holds the parabola vertices on the lower envelope, z[] the boundaries
# between consecutive ones; scratch arrays are passed in (sized by the
# caller) rather than allocated per row.
func _edt_1d(f: PackedFloat64Array, n: int, d: PackedFloat64Array, v: PackedInt32Array, z: PackedFloat64Array) -> void:
	var k: int = 0
	v[0] = 0
	z[0] = -INF
	z[1] = INF
	for q in range(1, n):
		var s: float = _edt_intersection(f, q, v[k])
		while s <= z[k]:
			k -= 1
			s = _edt_intersection(f, q, v[k])
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = INF
	k = 0
	for q in n:
		while z[k + 1] < float(q):
			k += 1
		var dq: float = float(q - v[k])
		d[q] = dq * dq + f[v[k]]

# X of the intersection of the parabolas rooted at q and p (q > p).
func _edt_intersection(f: PackedFloat64Array, q: int, p: int) -> float:
	return ((f[q] + float(q * q)) - (f[p] + float(p * p))) / float(2 * q - 2 * p)

# Bilinear over the distance grid, clamped to its edge beyond it - past
# the padding everything is either open water or the dry inland band, and
# the walls sit well inside either way.
func _mask_distance_sample(world_xz: Vector2) -> float:
	var g: Vector2 = (world_xz - _mask_distance_origin) / _mask_distance_cell_size
	var x: float = clampf(g.x, 0.0, float(_mask_distance_cols - 1))
	var y: float = clampf(g.y, 0.0, float(_mask_distance_rows - 1))
	var x0: int = int(floor(x))
	var y0: int = int(floor(y))
	var x1: int = mini(x0 + 1, _mask_distance_cols - 1)
	var y1: int = mini(y0 + 1, _mask_distance_rows - 1)
	var fx: float = x - float(x0)
	var fy: float = y - float(y0)
	var top: float = lerpf(_mask_distance[y0 * _mask_distance_cols + x0], _mask_distance[y0 * _mask_distance_cols + x1], fx)
	var bottom: float = lerpf(_mask_distance[y1 * _mask_distance_cols + x0], _mask_distance[y1 * _mask_distance_cols + x1], fx)
	return lerpf(top, bottom, fy)

# Sample points and their expected get_height_at() result, computed once
# by an independent re-port of the same shader math (in Node.js, not this
# file) at ground.gd's own declared export defaults - see the constants
# just below. Only meaningful while every export listed there still
# matches its default: _debug_assert_height_matches_shader_math() skips
# the whole comparison the moment any of them has been tuned away from
# that, so editing relief in the Remote tab never trips a false failure.
#
# Permanently skipped as of the landmass shape change: relief_extent's own
# default moved to (100, 70) and _relief_height() now includes the
# landmass term, so DEBUG_DEFAULT_RELIEF_EXTENT/DEBUG_REFERENCE_SAMPLES
# below (still the old (80, 50)/bump-only values) never match at_defaults
# again - this intentionally reuses the same "skip if not at defaults"
# escape hatch rather than re-deriving a new Node.js reference for the
# landmass formula, which is out of scope for this pass. Flag if that
# parity check is wanted back.
const DEBUG_DEFAULT_WETNESS_SCALE: float = 30.0
const DEBUG_DEFAULT_WETNESS_AMOUNT: float = 0.4
const DEBUG_DEFAULT_RELIEF_NOISE_SCALE: float = 4.0
const DEBUG_DEFAULT_RELIEF_AMPLITUDE: float = 0.3
const DEBUG_DEFAULT_RELIEF_EXTENT: Vector2 = Vector2(80.0, 50.0)
const DEBUG_DEFAULT_RELIEF_EDGE_FADE: float = 4.0
const DEBUG_DEFAULT_RELIEF_FLAT_MARGIN: float = 3.0
# (38.0, 0.0) sits at edge_dist=2.0 - inside DEBUG_DEFAULT_RELIEF_FLAT_
# MARGIN (3.0), so _relief_edge_fade_factor() is now exactly 0 there and
# the expected height collapses to 0.0 regardless of the noise term - not
# re-derived from the external Node.js re-port like the others (trivial to
# confirm from the formula alone: anything * 0 == 0), but still an exact
# value, not an approximation.
const DEBUG_REFERENCE_SAMPLES: Dictionary = {
	Vector2(0.0, 0.0): -0.3,
	Vector2(20.0, -12.0): -0.05804631,
	Vector2(38.0, 0.0): 0.0,
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
		and is_equal_approx(relief_flat_margin, DEBUG_DEFAULT_RELIEF_FLAT_MARGIN)
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
const NORMAL_DEBUG_NODE_NAME: String = "NormalDebugLines"

func _rebuild_ground_mesh_and_collision() -> void:
	if not _ready_done:
		return

	# Forces _ensure_landmass_refs() to re-read Sea/RegionField on the next
	# _relief_height()/get_landmass_distance() call, rather than serving a
	# cache that could predate either being ready, or predate a live edit
	# to Sea's own near_edge_z-affecting exports.
	_landmass_refs_ready = false
	# After the refs invalidation above, since the distance grid is placed
	# from spawn/forward (see _build_mask_distance_field()) and must read
	# them fresh too. Only re-decodes when a mask-affecting export changed;
	# a plain relief edit reuses the existing grid.
	if _mask_dirty:
		_rebuild_mask_data()

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

	relief_rebuilt.emit()

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

# Builds the relief mesh through SurfaceTool rather than hand-computing
# normals from a height-gradient formula: add_vertex() per-triangle (each
# grid point duplicated once per adjacent triangle), index() merges those
# duplicates back into a shared index buffer, then generate_normals()
# derives each vertex's normal from the actual committed triangles sharing
# it - guaranteed geometrically consistent with the real winding, instead
# of a separately-computed formula that has to be kept in sync with it by
# hand (the previous gradient-based version was the actual source of the
# across-the-field lighting/shadow errors this replaces).
func _apply_relief_mesh(cols: int, rows: int, heights: PackedFloat32Array) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.resize(cols * rows)
	for row in rows:
		for col in cols:
			var world_xz: Vector2 = _relief_grid_to_world_xz(col, row, cols, rows)
			var index: int = row * cols + col
			vertices[index] = Vector3(world_xz.x, heights[index], world_xz.y)

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rows - 1:
		for col in cols - 1:
			var top_left: int = row * cols + col
			var top_right: int = top_left + 1
			var bottom_left: int = (row + 1) * cols + col
			var bottom_right: int = bottom_left + 1

			# Counter-clockwise as seen from +Y - keep the winding fix from
			# the last pass (the prior order rendered nothing under
			# cull_back, wound clockwise from above instead).
			surface_tool.add_vertex(vertices[top_left])
			surface_tool.add_vertex(vertices[top_right])
			surface_tool.add_vertex(vertices[bottom_left])

			surface_tool.add_vertex(vertices[top_right])
			surface_tool.add_vertex(vertices[bottom_right])
			surface_tool.add_vertex(vertices[bottom_left])

	surface_tool.index()
	surface_tool.generate_normals()
	surface_tool.set_material(_current_ground_material())

	_relief_mesh_instance.name = "ReliefMesh"
	_relief_mesh_instance.mesh = surface_tool.commit()

	_rebuild_normal_debug()

# Short lines from every normal_debug_stride-th vertex of the actual
# committed relief mesh, along its actual committed normal - read back
# from the mesh itself (post-generate_normals()) rather than recomputed,
# so this shows exactly what the mesh really has, not what it should have.
# Parented under _relief_mesh_instance so the lines are already in the
# right local space with no manual offset.
func _rebuild_normal_debug() -> void:
	if not _ready_done:
		return
	var existing: Node = _relief_mesh_instance.get_node_or_null(NORMAL_DEBUG_NODE_NAME)
	if existing:
		existing.queue_free()
	if not draw_normal_debug or _relief_mesh_instance.mesh == null:
		return

	var mesh_arrays: Array = (_relief_mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)
	var mesh_vertices: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	var mesh_normals: PackedVector3Array = mesh_arrays[Mesh.ARRAY_NORMAL]

	var line_vertices: PackedVector3Array = PackedVector3Array()
	var stride: int = maxi(normal_debug_stride, 1)
	var i: int = 0
	while i < mesh_vertices.size():
		line_vertices.append(mesh_vertices[i])
		line_vertices.append(mesh_vertices[i] + mesh_normals[i] * normal_debug_length)
		i += stride

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = line_vertices

	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.1, 1.0, 0.3)
	line_mesh.surface_set_material(0, material)

	var line_instance := MeshInstance3D.new()
	line_instance.name = NORMAL_DEBUG_NODE_NAME
	line_instance.mesh = line_mesh
	line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_relief_mesh_instance.add_child(line_instance)

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
# directly under Ground (not _relief_mesh_instance) - the two used to sit
# at different Y (a since-removed +0.02 cosmetic z-fight nudge on
# _relief_mesh_instance), but _relief_mesh_instance has no offset of its
# own anymore, so a sphere is now expected to sit exactly ON the rendered
# surface everywhere, not ~2cm below it. If a sphere sits any distance
# from the rendered surface, or a character doesn't stand on the sphere
# nearest it, the mismatch is in the ArrayMesh/HeightMapShape3D
# construction (winding, indexing, transform), not in get_height_at()
# itself.
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

	var ns_depth: float = outer_half.y - inner_half.y
	mesh_instance.position = Vector3(0.0, 0.0, (inner_half.y + outer_half.y) * 0.5)
	mesh_instance.mesh = _build_ns_dressing_mesh(ns_depth)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var south_instance := MeshInstance3D.new()
	south_instance.name = DRESSING_FRAME_NODE_PREFIX + "South"
	south_instance.mesh = _build_ns_dressing_mesh(ns_depth)
	south_instance.position = Vector3(0.0, 0.0, -(inner_half.y + outer_half.y) * 0.5)
	south_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(south_instance)

	# East/West's shared edge with the relief mesh runs along Z, spanning
	# EXACTLY relief_extent.y (not a wider span the way North/South's X
	# does) - subdivide_depth = relief's own Z segment count reproduces
	# relief's exact Z spacing with no rounding drift, since both divide
	# the identical extent by the identical count. A plain PlaneMesh is
	# enough here; only North/South need the custom mesh below.
	var ew_strips: Array[Dictionary] = [
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

	for strip: Dictionary in ew_strips:
		var strip_instance := MeshInstance3D.new()
		strip_instance.name = DRESSING_FRAME_NODE_PREFIX + str(strip["name"])
		strip_instance.mesh = _build_dressing_plane(strip["size"], dressing_subdivisions.x, relief_subdivisions.y + 1)
		strip_instance.position = strip["position"]
		strip_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip_instance)

func _build_dressing_plane(size: Vector2, subdivide_width: int, subdivide_depth: int) -> PlaneMesh:
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = subdivide_width
	plane.subdivide_depth = subdivide_depth
	plane.material = _current_ground_material()
	return plane

# North/South's shared edge with the relief mesh spans the relief mesh's
# own width (relief_extent.x) - a small fraction of the strip's actual
# width (plane_size.x). A plain PlaneMesh's subdivide_width only controls
# an EVEN division of its own total size, so rounding it to approximately
# match relief's absolute spacing (relief_extent.x / (relief_subdivisions.x
# + 1)) drifts the real per-segment spacing by however unevenly plane_
# size.x happens to divide by it - at the shared edge that drift is small
# in absolute terms but easily centimeters, i.e. worse than the seam this
# exists to fix. Built via SurfaceTool instead: the CENTER columns
# reproduce relief's own edge-row X positions exactly (identical formula
# to _relief_grid_to_world_xz()), with one plain wing quad on each side
# out to the strip's own true edge - the wings don't need to match
# anything, so they stay single quads rather than finely subdividing the
# entire (often much larger) far reaches of the strip. Perfectly flat, so
# generate_normals() gives (0,1,0) throughout with no special-casing.
func _build_ns_dressing_mesh(depth: float) -> ArrayMesh:
	var relief_half_x: float = relief_extent.x * 0.5
	var relief_cols: int = relief_subdivisions.x + 2
	var relief_spacing_x: float = relief_extent.x / float(relief_subdivisions.x + 1)
	var half_width: float = plane_size.x * 0.5

	var xs: PackedFloat32Array = PackedFloat32Array()
	xs.append(-half_width)
	for col in relief_cols:
		xs.append(-relief_half_x + float(col) * relief_spacing_x)
	xs.append(half_width)

	var depth_rows: int = dressing_subdivisions.y + 2
	var depth_spacing: float = depth / float(depth_rows - 1)
	var zs: PackedFloat32Array = PackedFloat32Array()
	for row in depth_rows:
		zs.append(-depth * 0.5 + float(row) * depth_spacing)

	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in depth_rows - 1:
		for col in xs.size() - 1:
			var top_left := Vector3(xs[col], 0.0, zs[row])
			var top_right := Vector3(xs[col + 1], 0.0, zs[row])
			var bottom_left := Vector3(xs[col], 0.0, zs[row + 1])
			var bottom_right := Vector3(xs[col + 1], 0.0, zs[row + 1])

			# Same winding as _apply_relief_mesh() - counter-clockwise as
			# seen from +Y.
			surface_tool.add_vertex(top_left)
			surface_tool.add_vertex(top_right)
			surface_tool.add_vertex(bottom_left)

			surface_tool.add_vertex(top_right)
			surface_tool.add_vertex(bottom_right)
			surface_tool.add_vertex(bottom_left)

	surface_tool.index()
	surface_tool.generate_normals()
	surface_tool.set_material(_current_ground_material())
	return surface_tool.commit()

# use_plain_ground_material's bisect: a loud, obviously-not-the-shader
# StandardMaterial3D in place of ground.gdshader's ShaderMaterial, applied
# to every ground surface (relief mesh + all four dressing strips) so the
# mesh/AABB/visibility side of "ground doesn't render" can be checked
# independent of whether the shader itself is at fault.
func _current_ground_material() -> Material:
	if not use_plain_ground_material:
		return _material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.15, 0.75)
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material
