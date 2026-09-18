extends Theme
class_name BattleTheme

# UI is the dark element on a pale world and the pale element on a dark
# one - always the figure, never the ground. The battle UI is ink on the
# world, in the cards' own two tones: on a pale world ink is the cards'
# ink and bone is their bone; on a dark world the two swap. The cards
# themselves never invert (CardView keeps its own field_color/ink_color).

@export_group("On Pale World (default)")
@export var on_pale_panel_color: Color = Color(0.12, 0.13, 0.15, 1.0)
@export var on_pale_panel_light_color: Color = Color(0.19, 0.2, 0.22, 1.0)
@export var on_pale_text_color: Color = Color(0.92, 0.92, 0.9, 1.0)
@export var on_pale_ink: Color = Color(0.165, 0.165, 0.18, 1.0)
@export var on_pale_bone: Color = Color(0.94, 0.91, 0.86, 1.0)

@export_group("On Dark World")
@export var on_dark_panel_color: Color = Color(0.87, 0.84, 0.76, 1.0)
@export var on_dark_panel_light_color: Color = Color(0.8, 0.77, 0.68, 1.0)
@export var on_dark_text_color: Color = Color(0.16, 0.14, 0.11, 1.0)
@export var on_dark_ink: Color = Color(0.94, 0.91, 0.86, 1.0)
@export var on_dark_bone: Color = Color(0.165, 0.165, 0.18, 1.0)

# The one colour outside the cards' two tones: the toll keyline, under
# the Toll numeral (BattleResources). Never inverts.
@export var toll_rule_color: Color = Color(0.54, 0.50, 0.58, 1.0)

# DebugRow's F1 buttons (see BattleOverlay) are the only boxed controls
# left - a flat 1px outline in ink, no fill, under the "DebugButton"
# variation so the plain Button type stays unstyled.
const DEBUG_BUTTON_OUTLINE_PX := 1

# Applies one of the two value sets above to every colour this theme
# drives: the "Battle" ink/bone tokens every battle readout draws with
# (HPBar/EnemyStatus's battle style, BattleIntent, BattleResources,
# EndTurnButton, PileReadout), the older "CardFace" tokens the field-side
# readouts and BattleFeedback still read, Label's default font colour,
# and the DebugButton outline. Layout and fonts never change here, only
# these values. Called by RegionField._setup_field_hud() with its
# ui_on_dark_world switch, by BattleOverlay.enter_battle() with the same
# switch, and by the overlay's F2 debug flip.
func apply_value_set(on_dark_world: bool) -> void:
	var panel_color: Color = on_dark_panel_color if on_dark_world else on_pale_panel_color
	var panel_light_color: Color = on_dark_panel_light_color if on_dark_world else on_pale_panel_light_color
	var text_color: Color = on_dark_text_color if on_dark_world else on_pale_text_color
	var ink: Color = on_dark_ink if on_dark_world else on_pale_ink
	var bone: Color = on_dark_bone if on_dark_world else on_pale_bone

	set_color("ink", "Battle", ink)
	set_color("bone", "Battle", bone)
	set_color("toll_rule", "Battle", toll_rule_color)

	set_color("font_color", "Label", text_color)

	set_color("panel_color", "CardFace", panel_color)
	set_color("panel_light_color", "CardFace", panel_light_color)
	set_color("text_color", "CardFace", text_color)

	var debug_outline := StyleBoxFlat.new()
	debug_outline.bg_color = Color(bone, 0.0)
	debug_outline.draw_center = false
	debug_outline.border_color = ink
	debug_outline.set_border_width_all(DEBUG_BUTTON_OUTLINE_PX)
	debug_outline.set_content_margin_all(6.0)
	var debug_hover := debug_outline.duplicate() as StyleBoxFlat
	debug_hover.set_border_width_all(DEBUG_BUTTON_OUTLINE_PX + 1)
	set_type_variation("DebugButton", "Button")
	set_stylebox("normal", "DebugButton", debug_outline)
	set_stylebox("hover", "DebugButton", debug_hover)
	set_stylebox("pressed", "DebugButton", debug_hover)
	set_stylebox("focus", "DebugButton", debug_outline)
	set_stylebox("disabled", "DebugButton", debug_outline)
	set_color("font_color", "DebugButton", ink)
	set_color("font_hover_color", "DebugButton", ink)
	set_color("font_pressed_color", "DebugButton", ink)
	set_color("font_focus_color", "DebugButton", ink)
