extends Resource
class_name ContactShadowData

# The look of the soft pale pool under a figure (ContactShadow): one
# shared copy (field/contact_shadow.tres) for every figure, and an
# EnemyData may point at its own. Art Bible §7 - no pure black; the
# figure stays the darkest thing in its area, so the pool is a cool,
# darkened ground tone laid into the sand's colour, never a black wash.

# The tone the sand takes at the pool's middle (the Decal's albedo), and
# how much of it: 0 none, 1 the sand replaced outright.
@export var tint: Color = Color(0.40, 0.42, 0.46):
	set(value):
		tint = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var strength: float = 0.5:
	set(value):
		strength = value
		emit_changed()

# The pool's radii: the figure's own footprint (its capsule's radius, or
# its model's half-extents across and along it) times footprint_scale,
# plus footprint_margin_m all round - so the pool reaches out past the
# silhouette by about the same at any size, from the Wanderer, whose body
# hides the middle of it from the camera, to the Greyshelf.
@export var footprint_scale: float = 1.0:
	set(value):
		footprint_scale = value
		emit_changed()
@export var footprint_margin_m: float = 0.35:
	set(value):
		footprint_margin_m = value
		emit_changed()
# Size the pool from the figure's body alone, not with what is attached to
# it (the dragonfly's wings) - where the owner knows the difference
# (ContactShadow.body_footprint).
@export var footprint_from_body: bool = false:
	set(value):
		footprint_from_body = value
		emit_changed()
# How far out, as a fraction of the radius, the pool holds full strength
# before it eases to nothing at its edge. No hard edge at any value.
@export_range(0.0, 0.95, 0.01) var falloff_start: float = 0.55:
	set(value):
		falloff_start = value
		emit_changed()

# Metres the projection reaches up and down from the surface under the
# figure - deep enough to follow a dune face or a bank under its width.
@export var reach_m: float = 0.75:
	set(value):
		reach_m = value
		emit_changed()
# The Decal's upper and lower fade, over that reach.
@export_range(0.0, 1.0, 0.01) var edge_fade: float = 0.3:
	set(value):
		edge_fade = value
		emit_changed()
# Decal.normal_fade: 0 keeps every face, 1 only those facing straight up.
# 0: the crest rock's mesh carries no normals, and any fade drops the pool
# off its top. The sand never stands steep enough to streak, and a slab's
# side beside a figure only takes a soft contact darkening.
@export_range(0.0, 1.0, 0.01) var normal_fade: float = 0.0:
	set(value):
		normal_fade = value
		emit_changed()

# A figure off the surface under it (a hover, a leap): the pool fades to
# nothing at hover_fade_height_m and shrinks toward hover_min_scale of its
# size on the way, linearly.
@export var hover_fade_height_m: float = 2.0:
	set(value):
		hover_fade_height_m = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var hover_min_scale: float = 0.6:
	set(value):
		hover_min_scale = value
		emit_changed()

# Sand under the sea: the pool is gone by this depth below sea level, so
# wading leaves none showing up through the water.
@export var wade_fade_depth_m: float = 0.15:
	set(value):
		wade_fade_depth_m = value
		emit_changed()

# Whether the pool also lands on a standable prop under the figure (a
# basking slab, the crest rock) - and its height is measured from that
# prop's top there - or only ever on the sand.
@export var perch_surfaces: bool = true:
	set(value):
		perch_surfaces = value
		emit_changed()
# The render layers the pool projects onto: Ground's contact_layers, and
# a standable prop's standable_layers (with perch_surfaces). Nothing else
# - not the figures, the props or the sea - is on either.
@export_flags_3d_render var ground_layers: int = 1 << 18:
	set(value):
		ground_layers = value
		emit_changed()
@export_flags_3d_render var perch_layers: int = 1 << 17:
	set(value):
		perch_layers = value
		emit_changed()
