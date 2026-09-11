extends Node
# Registered as a scene autoload (sunken_works_palette.tscn, see project.
# godot's [autoload] section) - not a bare class_name/const script, same
# reasoning OverlayStyle already gives for itself: @export only shows up
# in the Inspector when the autoload has a scene to attach to, and these
# values are specifically meant to be eyeballed and retuned from there
# (placeholders today - see each var's own note), not baked constants a
# retune would mean editing this file's own source for.
#
# The Sunken Works' own battle background palette (see battle_background.
# gd, the one consumer today) - every background element reads its color
# from here rather than hardcoding one inline, so retuning the whole
# scene is a one-place edit. Named for the one biome that exists right
# now, not a generic/biome-agnostic palette - a second biome needing its
# own would be the point where this either gets parametrized per-biome
# or a sibling palette gets added; not before, per this task's own scope
# (background rendering only, not a multi-biome system nothing needs
# yet).
#
# STRUCTURE_FAR/STRUCTURE_NEAR are defined but unused this pass - no
# node reads them yet (see battle_background.gd's own header for what
# IS built this pass: sky + ground only). Defined now anyway so the
# palette is complete in one place ahead of whichever future pass adds
# structure silhouettes, rather than a second script appearing later
# with just those two colors in it.
#
# ALL_CAPS var names, unusual for an @export (GDScript convention is
# snake_case for a var, ALL_CAPS for a const) - kept exactly as named in
# the brief that asked for this, since these ARE effectively named
# constants from every consumer's perspective, just Inspector-editable
# ones rather than baked ones. Functionally a plain @export var either
# way; the naming is cosmetic.

@export var SKY_HIGH: Color = Color(0.55, 0.68, 0.78, 1)
# Placeholder - the sky's own zenith tone, top of the gradient.

@export var SKY_HORIZON: Color = Color(0.8, 0.82, 0.79, 1)
# Placeholder - paler and warmer than SKY_HIGH, same "sky gets hazier
# and warmer toward the horizon" read the real Sunken Works painting
# (SunkenWorks1.png) already has, bottom of the gradient.

@export var GROUND: Color = Color(0.33, 0.31, 0.28, 1)
# Placeholder - deliberately darker and less saturated than either sky
# color (see battle_background.gd's own note on why the ground reading
# too close to the sky in brightness was the actual complaint).

@export var GROUND_SHADOW: Color = Color(0.19, 0.18, 0.16, 1)
# Placeholder - darker still, the thin strip along the very bottom edge
# of the playfield (see battle_background.gd's own ground_shadow_height_
# px) that keeps the floor from reading as one flat slab.

@export var STRUCTURE_FAR: Color = Color(0.62, 0.66, 0.7, 1)
# Placeholder - unused this pass, see this file's own header.

@export var STRUCTURE_NEAR: Color = Color(0.4, 0.38, 0.36, 1)
# Placeholder - unused this pass, see this file's own header.
