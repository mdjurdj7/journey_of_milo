extends MeshInstance3D

@export var tower_color: Color = Color(0.30, 0.32, 0.33)
@export var height: float = 150.0
@export var base_radius: float = 9.0
@export var top_radius: float = 2.0

func _ready() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.height = height
	cylinder.bottom_radius = base_radius
	cylinder.top_radius = top_radius

	var material := StandardMaterial3D.new()
	material.albedo_color = tower_color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	cylinder.material = material

	mesh = cylinder
	# Position is baked into this node's own transform in region_field.tscn,
	# not set here - Ground._apply_water_line_uniforms() calls RegionField.
	# get_forward() from Ground's own _ready(), which (Ground being an
	# earlier sibling than Tower) runs before Tower's _ready() could apply
	# a script-computed offset. get_forward()'s spawn->Tower vector would
	# see Tower still at its scene-default (0,0,0), read zero length, and
	# permanently cache the -Z fallback. Baking the position into the node
	# transform instead makes it correct from the moment the scene loads -
	# before any node's _ready() runs at all.
	# A distant silhouette, not something the player stands near - its huge
	# size (150m tall) was eating the directional shadow's depth precision
	# for every other, much smaller caster in the scene. No shadow needed.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
