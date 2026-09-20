extends MeshInstance3D
class_name Tower

@export var tower_color: Color = Color(0.30, 0.32, 0.33)
# Region 1's own; what stands on floor 1. Every floor after it is taller
# by growth_per_floor of this - see _scaled_height().
@export var height: float = 150.0
@export var base_radius: float = 9.0
@export var top_radius: float = 2.0
# Fraction of `height` added per floor index: height x (1 + this x
# RunState.current_floor_index). The tower grows with depth (see docs/
# GAME_FRAMEWORK.md) - a touch per floor, read at scene load, which is
# once per floor since a floor change is a scene reload.
@export var growth_per_floor: float = 0.02

var _built_height: float = 0.0

func _ready() -> void:
	_built_height = _scaled_height()
	var cylinder := CylinderMesh.new()
	cylinder.height = _built_height
	cylinder.bottom_radius = base_radius
	cylinder.top_radius = top_radius

	var material := StandardMaterial3D.new()
	material.albedo_color = tower_color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	cylinder.material = material

	mesh = cylinder
	# The XZ position is baked into this node's own transform in
	# region_field.tscn, not set here - Ground._apply_water_line_uniforms()
	# calls RegionField.get_forward() from Ground's own _ready(), which
	# (Ground being an earlier sibling than Tower) runs before Tower's
	# _ready() could apply a script-computed offset. get_forward()'s
	# spawn->Tower vector would see Tower still at its scene-default
	# (0,0,0), read zero length, and permanently cache the -Z fallback.
	# Baking the position into the node transform instead makes it correct
	# from the moment the scene loads - before any node's _ready() runs at
	# all. Only Y is set here, and only so the base stays on the ground as
	# the height grows: a CylinderMesh is centred on its node.
	position.y = _built_height / 2.0
	# A distant silhouette, not something the player stands near - its huge
	# size (150m tall) was eating the directional shadow's depth precision
	# for every other, much smaller caster in the scene. No shadow needed.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _scaled_height() -> float:
	return height * (1.0 + growth_per_floor * float(RunState.current_floor_index))

# The foot of the tower in world space - what the camera lifts its eyes
# to at a floor's threshold (CameraRig.look_up()).
func get_base_position() -> Vector3:
	return Vector3(global_position.x, global_position.y - _built_height / 2.0, global_position.z)
