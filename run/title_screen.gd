extends Control
class_name TitleScreen

# The boot scene (project.godot's run/main_scene): one flat colour for
# the second the field takes to load, and a flag. Nothing here is the
# title itself - that is TitleMenu, shown by ZoneIntro over the field's
# own frame zero (ZoneIntro.hold_title(): the field loaded, the camera in
# the opening pose, the fog closed so only the tower shows), so that
# Start responds at once with no scene change behind it and the type
# sits on the rendered fog rather than a flat rect. This scene raises
# RunState.title_pending, lets its own frame draw, and changes to the
# field; RegionField._ready() consumes the flag and holds the title
# instead of playing the intro outright. F6 on the field never passes
# through here, so it keeps starting a run with the intro, no title;
# RunOver's Restart likewise.

const FIELD_SCENE_PATH := "res://field/region_field.tscn"

# The only flat colour left in the flow - matched by eye to the fog as
# it renders (AgX and the adjustments darken the raw fog colour), so the
# field's first frame doesn't step. Re-applies live.
@export var background_color: Color = Color(0.86, 0.87, 0.86, 1.0):
	set(value):
		background_color = value
		if background != null:
			background.color = value

@onready var background: ColorRect = $Background

func _ready() -> void:
	background.color = background_color
	RunState.title_pending = true
	_boot()

# One drawn frame of this colour before the load: the scene change is
# flushed at the end of a process step, before that step's frame draws,
# so asked for from _ready() it would swap in the field - a ~1 s blocking
# load - before this scene ever rendered. Waiting for the first frame to
# be drawn puts the colour on screen for the load's duration instead.
func _boot() -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	get_tree().change_scene_to_file(FIELD_SCENE_PATH)
