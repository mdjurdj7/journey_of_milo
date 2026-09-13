extends RefCounted
class_name HoverRaycast

# Shared "is this specific 3D body under the mouse right now" check - same
# raycast technique BattleController._raycast_enemy() already uses for
# card-targeting hover, generalized to any single Node3D target rather
# than a list of enemies (HPBar/EnemyStatus's own field-hover visibility
# each only ever care about their own one target).
static func is_hovering(viewport: Viewport, target: Node3D, max_distance: float = 1000.0) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return false
	var screen_pos: Vector2 = viewport.get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * max_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var space_state: PhysicsDirectSpaceState3D = viewport.get_world_3d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var collider: Object = result.get("collider")
	return collider == target
