extends MeshInstance3D
class_name Tower

# The tower as seen from Region 1: an unresolved pale silhouette at
# extreme distance, its shape nearly merging with the atmosphere (Bible
# S5). A landmark, NOT an axis - the field's forward comes from
# RegionField's ForwardMarker, so this node can stand wherever the
# battle frame wants it (west of the flat today, where the side-on battle
# camera looks) without turning the field. Nothing in the field walk
# reads its position; CameraRig.look_up() does at a floor's threshold,
# through get_base_position().
#
# Rendering: fog is what hides everything past 28 m here (RegionSky's
# depth fog is fully opaque by then), so this material opts out of it -
# unshaded, no fog - and paints itself the fog colour darkened by
# tower_contrast. It is therefore "visible" from anywhere; what keeps it
# out of the field walk is geometry alone: the field camera's top edge
# sits ~25 deg below the horizon and the whole tower stands above it -
# pitch_degrees would have to drop from 50 to ~22.5 before its foot broke
# the frame. The side-on battle frame at battle_pitch 12 holds ~5.5 deg
# of sky, and that is where it shows.

@export_group("Shape")
# Metres, before floor growth (see growth_per_floor). Every export here
# re-applies live - each setter rebuilds the mesh.
@export var tower_height: float = 120.0:
	set(value):
		tower_height = value
		_rebuild()
@export var base_radius: float = 7.0:
	set(value):
		base_radius = value
		_rebuild()
@export var top_radius: float = 3.0:
	set(value):
		top_radius = value
		_rebuild()
# The asymmetry: 0 tapers evenly all round, 1 leaves one face dead
# vertical with all the taper on the far side (the top ring's centre
# slides toward the straight face by (base_radius - top_radius) x this).
@export_range(0.0, 1.0) var straight_side_bias: float = 0.65:
	set(value):
		straight_side_bias = value
		_rebuild()
# Which way (world yaw, degrees, 0 = +X) the straight face looks.
@export var straight_side_yaw_degrees: float = 0.0:
	set(value):
		straight_side_yaw_degrees = value
		_rebuild()
@export_range(3, 64) var sides: int = 16:
	set(value):
		sides = value
		_rebuild()
# Fraction of the whole tower added per floor index: every dimension x
# (1 + this x RunState.current_floor_index). The tower grows with depth
# (see docs/GAME_FRAMEWORK.md) - a touch per floor, read at rebuild,
# which is once per floor since a floor change is a scene reload.
@export var growth_per_floor: float = 0.02:
	set(value):
		growth_per_floor = value
		_rebuild()
# World Y of the foot. The mesh is built from here upward whatever the
# node's own Y, so the base never lifts off the ground as the height
# grows - and the node transform in region_field.tscn stays a plain XZ
# placement.
@export var base_world_y: float = 0.0:
	set(value):
		base_world_y = value
		_rebuild()

@export_group("Silhouette")
# How much darker than the fog it is drawn, as a fraction in linear
# light: 0 disappears into the haze entirely, 0.06 is barely there.
@export_range(0.0, 1.0) var tower_contrast: float = 0.06:
	set(value):
		tower_contrast = value
		_rebuild()
# The foot dissolves into the fog over this many metres (its bottom ring
# is exactly fog-coloured) - past the fog wall there is nothing behind
# the tower but flat fog colour, and a hard bottom edge hanging just
# under the horizon line would read as a cut-out, not a distant mass.
@export var foot_fade_height: float = 30.0:
	set(value):
		foot_fade_height = value
		_rebuild()
# Where the fog colour comes from: RegionSky's own fog_color. Same value
# the sky and the depth fog are painted with, so the match holds through
# tonemapping and the colour adjustments, which hit all three alike.
@export var sky_path: NodePath = ^"../WorldEnvironment"
# Used when no RegionSky is found at sky_path (scene edited standalone).
@export var fog_color_fallback: Color = Color(0.86, 0.87, 0.86):
	set(value):
		fog_color_fallback = value
		_rebuild()

var _material: StandardMaterial3D

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Opts out of RegionSky's depth fog - the one thing that lets a mass
	# 400 m out draw at all when everything else is gone by 28.
	_material.disable_fog = true
	# The foot fade is baked into the vertices (see _build_mesh()) as a
	# grey multiplier on the fog colour in albedo_color.
	_material.vertex_color_use_as_albedo = true
	_material.disable_receive_shadows = true
	# Both faces draw the same flat colour, so winding can never lose one.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _material
	# A distant silhouette, not something the player stands near - at this
	# size it was eating the directional shadow's depth precision for every
	# other, much smaller caster in the scene. Unshaded anyway; no shadow
	# either way.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rebuild()

func _floor_scale() -> float:
	return 1.0 + growth_per_floor * float(RunState.current_floor_index)

func _fog_color() -> Color:
	var sky := get_node_or_null(sky_path) as RegionSky
	return sky.fog_color if sky != null else fog_color_fallback

# Guarded so the setters can fire during scene deserialization, before
# _ready() has made the material.
func _rebuild() -> void:
	if _material == null or not is_inside_tree():
		return
	_material.albedo_color = _fog_color()
	mesh = _build_mesh()

# A tapering frustum built from three rings - the foot, the top of the
# foot fade, and the top - closed with a cap. Vertex colour carries the
# foot fade: (1 - tower_contrast) from the fade ring up, rising to 1.0
# (pure fog colour) at the foot. Three rings are all a silhouette this
# flat needs; nothing between them would change a straight-sided outline.
func _build_mesh() -> ArrayMesh:
	var scale_factor: float = _floor_scale()
	var height: float = maxf(tower_height * scale_factor, 0.01)
	var foot_radius: float = base_radius * scale_factor
	var crown_radius: float = top_radius * scale_factor
	var foot_y: float = base_world_y - global_position.y
	var fade_t: float = clampf(foot_fade_height * scale_factor / height, 0.0, 0.999)
	var straight_dir := Vector2(cos(deg_to_rad(straight_side_yaw_degrees)), sin(deg_to_rad(straight_side_yaw_degrees)))

	var ring_ts: PackedFloat32Array = PackedFloat32Array([0.0, fade_t, 1.0])
	var ring_weights: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 1.0])

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_starts: PackedInt32Array = PackedInt32Array()
	var vertex_count: int = 0
	for ring in ring_ts.size():
		var t: float = ring_ts[ring]
		var radius: float = lerpf(foot_radius, crown_radius, t)
		# The ring's centre slides toward the straight face by however much
		# the radius has shrunk, scaled by the bias - at bias 1 that face's
		# outer edge stays at exactly foot_radius all the way up.
		var centre: Vector2 = straight_dir * (foot_radius - radius) * straight_side_bias
		var y: float = foot_y + height * t
		var shade: float = 1.0 - tower_contrast * ring_weights[ring]
		ring_starts.append(vertex_count)
		for side in sides:
			var angle: float = TAU * float(side) / float(sides)
			surface.set_color(Color(shade, shade, shade, 1.0))
			surface.add_vertex(Vector3(centre.x + cos(angle) * radius, y, centre.y + sin(angle) * radius))
			vertex_count += 1

	for ring in ring_ts.size() - 1:
		var lower: int = ring_starts[ring]
		var upper: int = ring_starts[ring + 1]
		for side in sides:
			var next_side: int = (side + 1) % sides
			surface.add_index(lower + side)
			surface.add_index(upper + side)
			surface.add_index(upper + next_side)
			surface.add_index(lower + side)
			surface.add_index(upper + next_side)
			surface.add_index(lower + next_side)

	# The cap: a fan from the top ring's own centre.
	var top_centre: Vector2 = straight_dir * (foot_radius - crown_radius) * straight_side_bias
	var top_shade: float = 1.0 - tower_contrast
	surface.set_color(Color(top_shade, top_shade, top_shade, 1.0))
	surface.add_vertex(Vector3(top_centre.x, foot_y + height, top_centre.y))
	var cap_centre: int = vertex_count
	var top_start: int = ring_starts[ring_starts.size() - 1]
	for side in sides:
		surface.add_index(cap_centre)
		surface.add_index(top_start + side)
		surface.add_index(top_start + (side + 1) % sides)

	return surface.commit()

# The foot of the tower in world space - what the camera lifts its eyes
# to at a floor's threshold (CameraRig.look_up()).
func get_base_position() -> Vector3:
	return Vector3(global_position.x, base_world_y, global_position.z)
