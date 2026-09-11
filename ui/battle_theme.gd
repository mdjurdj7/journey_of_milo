extends Theme
class_name BattleTheme

# UI is the dark element on a pale world and the pale element on a dark
# one - always the figure, never the ground.

@export_group("On Pale World (default)")
@export var on_pale_panel_color: Color = Color(0.12, 0.13, 0.15, 1.0)
@export var on_pale_panel_light_color: Color = Color(0.19, 0.2, 0.22, 1.0)
@export var on_pale_text_color: Color = Color(0.92, 0.92, 0.9, 1.0)

@export_group("On Dark World")
@export var on_dark_panel_color: Color = Color(0.87, 0.84, 0.76, 1.0)
@export var on_dark_panel_light_color: Color = Color(0.8, 0.77, 0.68, 1.0)
@export var on_dark_text_color: Color = Color(0.16, 0.14, 0.11, 1.0)

const BUTTON_CORNER_RADIUS := 6

# Applies one of the two value sets above to every color/style this theme
# drives: Button (and PanelContainer, styled to match it - see StatsPanel),
# Label's default font color, and the "CardFace" colors hand_container.gd
# reads for the card body/art-region/text/badge. Layout and fonts never
# change here, only these values. Called by BattleOverlay.enter_battle()
# with RegionField's own ui_on_dark_world switch.
func apply_value_set(on_dark_world: bool) -> void:
	var panel_color: Color = on_dark_panel_color if on_dark_world else on_pale_panel_color
	var panel_light_color: Color = on_dark_panel_light_color if on_dark_world else on_pale_panel_light_color
	var text_color: Color = on_dark_text_color if on_dark_world else on_pale_text_color

	var button_normal := StyleBoxFlat.new()
	button_normal.bg_color = panel_color
	button_normal.corner_radius_top_left = BUTTON_CORNER_RADIUS
	button_normal.corner_radius_top_right = BUTTON_CORNER_RADIUS
	button_normal.corner_radius_bottom_right = BUTTON_CORNER_RADIUS
	button_normal.corner_radius_bottom_left = BUTTON_CORNER_RADIUS
	button_normal.shadow_size = 0

	var button_hover := button_normal.duplicate() as StyleBoxFlat
	button_hover.bg_color = panel_light_color

	var button_pressed := button_normal.duplicate() as StyleBoxFlat
	button_pressed.bg_color = panel_color.darkened(0.15)

	set_stylebox("normal", "Button", button_normal)
	set_stylebox("hover", "Button", button_hover)
	set_stylebox("pressed", "Button", button_pressed)
	set_stylebox("focus", "Button", button_normal)
	set_stylebox("disabled", "Button", button_normal)
	set_color("font_color", "Button", text_color)
	set_color("font_hover_color", "Button", text_color)
	set_color("font_pressed_color", "Button", text_color)
	set_color("font_focus_color", "Button", text_color)

	# StatsPanel (the HP/Toll box) is a plain PanelContainer with no
	# variation of its own - it matches End Turn by reusing its exact
	# stylebox, not a second, separately-tuned one.
	set_stylebox("panel", "PanelContainer", button_normal)

	set_color("font_color", "Label", text_color)

	set_color("panel_color", "CardFace", panel_color)
	set_color("panel_light_color", "CardFace", panel_light_color)
	set_color("text_color", "CardFace", text_color)
	set_color("badge_bg_color", "CardFace", text_color)
	set_color("badge_fg_color", "CardFace", panel_color)
