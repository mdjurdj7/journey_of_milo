extends MeshInstance3D
class_name NavDebugDraw

# Debug builds only - the field F1 row's Path toggle (RegionField._setup_
# debug_row()): the Wanderer's planned walk as a line from him through
# every waypoint left, and the walk grid's cells near him (NavGrid) - a
# cross on each blocked cell and a small square on each shallow one - all
# lifted a little off the ground, unshaded, redrawn every frame it shows.
# Contact zones are stamped per plan and lifted again, so they never show.

@export var draw_radius: float = 6.0
@export var lift: float = 0.08
@export var path_color: Color = Color(0.85, 0.15, 0.1)
@export var blocked_color: Color = Color(0.1, 0.1, 0.12)
@export var shallow_color: Color = Color(0.15, 0.4, 0.85)

var _field: RegionField = null
var _mesh: ImmediateMesh = null

func setup(field: RegionField) -> void:
	_field = field

func _ready() -> void:
	# World-space lines: off the parent's transform, at the origin.
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	if not visible or _field == null or _field.wanderer == null:
		return
	var grid: NavGrid = _field.get_nav_grid()
	var wanderer: Wanderer = _field.wanderer
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var drew: bool = false
	if grid != null:
		var centre: Vector2i = grid.world_to_cell(Vector2(wanderer.global_position.x, wanderer.global_position.z))
		var reach: int = int(ceil(draw_radius / grid.cell_size))
		var half: float = grid.cell_size * 0.35
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var cell := Vector2i(centre.x + dx, centre.y + dz)
				if not grid.in_bounds(cell) or Vector2(dx, dz).length() > float(reach):
					continue
				var at: Vector2 = grid.cell_centre(cell)
				var y: float = grid.height_at_cell(cell) + lift
				if grid.astar.is_point_solid(cell):
					_line(Vector3(at.x - half, y, at.y - half), Vector3(at.x + half, y, at.y + half), blocked_color)
					_line(Vector3(at.x - half, y, at.y + half), Vector3(at.x + half, y, at.y - half), blocked_color)
					drew = true
				elif grid.water[cell.y * grid.cols + cell.x] == 1:
					var q: float = half * 0.5
					_line(Vector3(at.x - q, y, at.y - q), Vector3(at.x + q, y, at.y - q), shallow_color)
					_line(Vector3(at.x + q, y, at.y - q), Vector3(at.x + q, y, at.y + q), shallow_color)
					_line(Vector3(at.x + q, y, at.y + q), Vector3(at.x - q, y, at.y + q), shallow_color)
					_line(Vector3(at.x - q, y, at.y + q), Vector3(at.x - q, y, at.y - q), shallow_color)
					drew = true
	var path: PackedVector3Array = wanderer.get_move_path()
	var previous: Vector3 = wanderer.global_position
	for point in path:
		_line(previous + Vector3.UP * lift, point + Vector3.UP * lift, path_color)
		previous = point
		drew = true
	if not drew:
		# An empty surface is an error; a zero-length line is nothing.
		_line(Vector3.ZERO, Vector3.ZERO, path_color)
	_mesh.surface_end()

func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(b)
