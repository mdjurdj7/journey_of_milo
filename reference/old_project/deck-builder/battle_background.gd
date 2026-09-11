extends Control
class_name BattleBackground
# The battle screen's fallback background - sky gradient, ground, and a
# darker ground-shadow strip, replacing the old flat single-color
# fallback (BiomeData.backdrop_fallback_color, removed - see biome_data.
# gd's own history). Every color reads from SunkenWorksPalette (the
# autoload, see its own header) rather than being hardcoded here, so a
# retune is a one-place edit to that palette's own Inspector values, not
# a search through this script.
#
# Sits in battle.tscn exactly where BackdropColor used to (same "always
# present, ColorRect-shaped fallback" role) - BackdropTexture still
# draws ON TOP of this and still fully covers it whenever a biome has
# real art (Sunken Works, today, via SunkenWorks1.png), so this is
# currently invisible in an actual Sunken Works battle. It exists for
# whichever biome doesn't have art yet, the same reason backdrop_
# fallback_color existed before it - not dead code, just not the thing
# on screen right now. See battle.gd's own _apply_battle_backdrop().
#
# Three children, drawn in this order (Godot draws earlier siblings
# first, so later ones sit on top): Ground (a plain full-rect ColorRect,
# the base layer), Sky (a TextureRect holding a GradientTexture2D,
# covering only the top horizon_y_px and overlapping Ground's own upper
# portion), GroundShadow (a thin ColorRect strip at the very bottom,
# overlapping Ground's own lower edge). Positioning both child rects
# reads from THIS script's own exported horizon_y_px/ground_shadow_
# height_px rather than being baked as fixed offsets on the children
# themselves, so both knobs live in the one place described above.

@export var horizon_y_px: float = 460.0
# Roughly where combatants' own feet/HP bars sit (see enemy.gd's/player_
# battle_visual.gd's shared bar_top_px = 420, plus a little clearance) -
# not derived from that value automatically, since this background lays
# out once at _ready() with no notion of either character cluster.

@export var ground_shadow_height_px: float = 40.0

@onready var sky: TextureRect = $Sky
@onready var ground: ColorRect = $Ground
@onready var ground_shadow: ColorRect = $GroundShadow

func _ready() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, SunkenWorksPalette.SKY_HIGH)
	gradient.set_color(1, SunkenWorksPalette.SKY_HORIZON)
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill = GradientTexture2D.FILL_LINEAR
	gradient_texture.fill_from = Vector2(0.5, 0.0)
	gradient_texture.fill_to = Vector2(0.5, 1.0)
	sky.texture = gradient_texture
	sky.anchor_right = 1.0
	sky.offset_bottom = horizon_y_px

	ground.anchor_right = 1.0
	ground.anchor_bottom = 1.0
	ground.color = SunkenWorksPalette.GROUND

	ground_shadow.anchor_top = 1.0
	ground_shadow.anchor_right = 1.0
	ground_shadow.anchor_bottom = 1.0
	ground_shadow.offset_top = -ground_shadow_height_px
	ground_shadow.color = SunkenWorksPalette.GROUND_SHADOW
