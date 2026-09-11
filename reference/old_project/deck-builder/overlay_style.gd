extends Node
# Registered as a scene autoload (overlay_style.tscn, see project.godot's
# [autoload] section) - not a bare script one, for the same reason
# RunState/RoomState already are (see run_state.gd's own header comment):
# @export only shows up in the Inspector when the autoload has a scene to
# attach to, and these values are specifically meant to be eyeballed and
# retuned, not baked constants.
#
# --- UI convention (DECIDED - see DESIGN.md) ---
#
# ONE shared legibility treatment for every combat overlay element that
# sits directly over the battle backdrop - a text outline / icon drop
# shadow, deliberately NOT a background panel. A panel reads as UI chrome
# sitting on top of the scene; an outline is direction-agnostic contrast
# (unlike a drop shadow alone, which only helps on the side it falls away
# from) that stays legible regardless of what's actually behind it -
# bright open sky, a shadowed structure, a busy tangle of ruins - without
# adding visual weight of its own. This is Enemy's own flavor-text
# reasoning (see enemy.gd's older Flavor Text Legibility note, now
# generalized here) extended to every OTHER overlay element that shares
# the exact same problem: reading over a detailed, variable-brightness
# image instead of a flat gray placeholder.
#
# Before this, FOUR different elements each carried their own
# independent copy of this exact idea, at four different widths/colors
# (block_badge.gd's value_outline_size at 5, status_badge.gd's at 3,
# enemy.gd's flavor_outline_size at 3, vitals_bar.tscn's HP number baked
# directly in the scene at 4 with no script knob at all) - and four MORE
# elements had no legibility treatment at all (the intent display's icon
# and number, floating damage numbers, the enemy name introduction).
# Every one of those eight now reads from here instead, so retuning the
# outline once retunes it everywhere - see apply_to_label()/
# make_icon_shadow() below for the two things every consumer actually
# needs (Label text, and Polygon2D-based icon shapes, which have no
# native outline property the way Label does).

@export var outline_color: Color = Color(0, 0, 0, 1)
@export var outline_width: int = 4
@export_range(0.0, 1.0, 0.01) var outline_opacity: float = 0.85
# Opacity deliberately kept as its OWN knob rather than folded into
# outline_color's own alpha channel (the shape every one of the four
# pre-existing copies actually used) - a color picker's alpha slider is
# easy to miss during a tuning pass; a dedicated one is what a future
# retune will actually reach for. Combined at apply time (see color()
# below), which is also what keeps every consumer from needing to do
# that math itself.

@export var light_outline_color: Color = Color(1, 1, 1, 1)
# For the inverted case (dark base text, light outline) - see enemy.gd's
# FlavorLabel/DefeatFlavorLabel, the one consumer so far that needs it.
# Every OTHER overlay element sits mostly over sky/structure and reads
# fine as light-text/dark-outline; flavor text sits at a fixed height
# beneath the HP bar that's always over the (bright, warm-gray) ground
# instead, where light-on-light was the actual problem no amount of
# outline width could fix - the base fill color needed to invert, and
# the outline has to invert with it or it stops contrasting the fill.
# Shares outline_width/outline_opacity with the dark case rather than
# getting its own copies - only the COLOR needs to flip per consumer,
# not the weight/strength of the treatment.

func color() -> Color:
	return Color(outline_color.r, outline_color.g, outline_color.b, outline_opacity)

func light_color() -> Color:
	return Color(light_outline_color.r, light_outline_color.g, light_outline_color.b, outline_opacity)

# Applies the shared outline to any Label showing text directly over the
# backdrop - Godot's own built-in outline rendering (one extra draw pass
# under the glyph, not a second competing node), the same mechanism
# every one of the four pre-existing copies already used internally,
# just no longer duplicated per file. Safe to call from a caller's own
# _ready() same as those did. use_light_outline is for a caller whose
# own base text color is dark rather than light (see light_outline_color
# above) - false (the common case) keeps the original dark-outline
# behavior unchanged for every existing consumer. width_override lets a
# caller with an unusually hard-to-read spot (see enemy.gd's flavor
# text, sitting over the backdrop's brightest ground) go thicker than
# the shared outline_width without forking its own copy of this whole
# function - still one shared mechanism, just a per-consumer knob on
# top of it, same spirit as use_light_outline above. opacity_override is
# the same idea in the other direction - a caller whose own base text
# already carries enough weight/contrast on its own (see enemy.gd's
# flavor text once it went back to solid white) can go FAINTER than the
# shared outline_opacity, for a supportive edge rather than a dominant
# one.
func apply_to_label(label: Label, use_light_outline: bool = false, width_override: int = -1, opacity_override: float = -1.0) -> void:
	var outline_col := light_color() if use_light_outline else color()
	if opacity_override >= 0.0:
		outline_col.a = opacity_override
	label.add_theme_color_override("font_outline_color", outline_col)
	label.add_theme_constant_override("outline_size", width_override if width_override >= 0 else outline_width)

# Polygon2D/Line2D (every intent icon's own shapes - see intent_display.
# gd) have no native outline property the way Label does, so icons get a
# drop shadow instead: a second instance of the same icon scene, every
# shape descendant recolored to the shared outline color, nudged
# down-right by outline_width. Returns the ready-to-add shadow node -
# the caller is responsible for adding it to the tree BEFORE the real
# icon (earlier siblings draw first, so this is what actually puts it
# behind rather than on top). Relies on the instantiated scene's shapes
# already existing the moment instantiate() returns, BEFORE this node is
# ever added to a live tree - true for every hand-authored Polygon2D
# icon in ICON_SCENES (see intent_display.gd's own doc on that
# dictionary), and true for the procedurally-built IDLE ring
# (intent_icon_idle.gd) too, but only because IT builds its own Line2D
# eagerly (custom setters, not a _ready() callback) for exactly this
# reason.
func make_icon_shadow(scene: PackedScene) -> Node2D:
	var shadow := scene.instantiate() as Node2D
	_tint_shapes(shadow, color())
	shadow.position += Vector2(outline_width, outline_width)
	return shadow

func _tint_shapes(node: Node, tint: Color) -> void:
	if node is Polygon2D:
		(node as Polygon2D).color = tint
	elif node is Line2D:
		(node as Line2D).default_color = tint
	for child in node.get_children():
		_tint_shapes(child, tint)
