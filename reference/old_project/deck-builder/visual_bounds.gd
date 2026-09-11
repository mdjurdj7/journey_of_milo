extends RefCounted
class_name VisualBounds
# Computes a Node2D's rendered bounding box, in the LOCAL space of
# whatever root node you pass in, from that root's direct children -
# used to bottom-anchor enemy silhouettes generically (see enemy.gd's
# _apply_creature_layout()), regardless of what kind of node actually
# draws the shape. Same "one small RefCounted helper" shape as
# WeightedRandom/EnemyPool - one place decides how to read a node's
# bounds, so nothing else in the game needs to know or care whether a
# given enemy is still a hand-drawn Polygon2D or, later, real art on a
# Sprite2D/AnimatedSprite2D. Add a new branch in _bounds_for() (not
# anywhere else) if a future visual ever needs another 2D node type.

static func compute(root: Node2D) -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	for child in root.get_children():
		if not (child is Node2D):
			continue
		var child_bounds: Variant = _bounds_in_parent_space(child)
		if child_bounds == null:
			continue
		bounds = child_bounds if not has_bounds else bounds.merge(child_bounds)
		has_bounds = true
	return bounds

# `node`'s own bounds, transformed into ITS PARENT's local space (i.e.
# ready to merge directly into the caller's own bounds Rect2, one level
# up) - child.transform accounts for node's own position/scale/rotation
# relative to its parent, so every node's bounds land in a shared space
# before combining, regardless of how each piece happens to be placed.
#
# If node isn't itself something _bounds_for() knows how to measure, this
# recurses into ITS children instead and merges THEIR bounds - a bare
# Node2D wrapper (e.g. player_visual.gd's FigureRoot, which exists only
# so a single scale.x flip mirrors every drawable piece underneath it at
# once, without that scale living on the SAME node an external caller
# might also want to scale - see PlayerBattleVisual) is invisible to
# bounds computation on its own, but its drawable descendants still count.
static func _bounds_in_parent_space(node: Node2D) -> Variant:
	var own_bounds: Variant = _bounds_for(node)
	if own_bounds != null:
		return node.transform * (own_bounds as Rect2)

	var merged := Rect2()
	var has_bounds := false
	for child in node.get_children():
		if not (child is Node2D):
			continue
		var child_bounds: Variant = _bounds_in_parent_space(child)
		if child_bounds == null:
			continue
		merged = child_bounds if not has_bounds else merged.merge(child_bounds)
		has_bounds = true
	if not has_bounds:
		return null
	return node.transform * merged

# Returns null (not an empty Rect2 - a real shape could legitimately be
# a single point) for anything this doesn't know how to measure, or that
# has nothing to measure yet (e.g. a Sprite2D with no texture assigned).
static func _bounds_for(node: Node2D) -> Variant:
	# Explicit casts, not just the `is` check above - node's static type
	# is Node2D, which doesn't have .polygon/.texture/.sprite_frames, so
	# GDScript needs the cast to allow accessing those in the branch
	# below even though the `is` check already guarantees it's safe.
	if node is Polygon2D:
		return _polygon_bounds((node as Polygon2D).polygon)
	if node is Sprite2D:
		return _sprite_bounds(node as Sprite2D)
	if node is AnimatedSprite2D:
		return _animated_sprite_bounds(node as AnimatedSprite2D)
	return null

static func _polygon_bounds(points: PackedVector2Array) -> Variant:
	if points.is_empty():
		return null
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	return rect

static func _sprite_bounds(sprite: Sprite2D) -> Variant:
	if sprite.texture == null:
		return null
	return _texture_bounds(sprite.texture.get_size(), sprite.centered, sprite.offset)

static func _animated_sprite_bounds(sprite: AnimatedSprite2D) -> Variant:
	if sprite.sprite_frames == null or sprite.animation == "":
		return null
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return null
	return _texture_bounds(texture.get_size(), sprite.centered, sprite.offset)

# Shared by both sprite types above - a texture's own bounds in ITS
# node's local space, before that node's own transform is applied (the
# caller, compute(), applies child.transform on top of this).
static func _texture_bounds(size: Vector2, centered: bool, offset: Vector2) -> Rect2:
	var top_left := -size / 2.0 if centered else Vector2.ZERO
	return Rect2(top_left + offset, size)

# Like compute(), but restricts the result to only the geometry lying
# within the bottom `slice_fraction` of root's OWN full silhouette height -
# an approximation of an entity's ground footprint rather than its total
# visual extent, so a raised weapon arm or a flared cape doesn't widen a
# contact shadow that should only span the feet (2026-09-01, battle
# grounding pass, footprint-measurement fix).
#
# compute() alone can't do this: it only ever returns a bounding Rect2, and
# a rectangle has the same width at every height - "slicing" one after the
# fact is a no-op for any source whose OWN bounds are already an axis-
# aligned rectangle (every Sprite2D/AnimatedSprite2D, via _texture_bounds()
# above - see this pass's own investigation report, which is what caught
# this). This needs the real underlying geometry - Polygon2D vertices, or
# a Sprite2D's own opaque pixels - filtered by position, not a Rect2
# merged after the fact. _collect_points() below does that: it walks the
# same tree compute() does, but gathers actual points (in root's own local
# space) instead of merging Rect2s, so this can filter by y before ever
# reducing anything to a rectangle.
#
# Falls back to compute()'s own full bounds in two cases, not just one:
# an EMPTY slice (shouldn't happen for real silhouettes - their lowest
# point is always AT the full bounds' bottom edge by construction), and a
# PATHOLOGICALLY NARROW one - a tapered shape whose bottom is a single
# point rather than a flat base (confirmed live: field_curio.gd's own
# diamond marker, [(0,-size), (half,-half), (0,0), (-half,-half)] - vertex
# (0,0) IS the entire bottom edge, a single point with zero width) would
# otherwise report a near-zero-width slice, which EntityShadow.attach()'s
# own `width <= 0.0` guard then turns into NO SHADOW AT ALL rather than a
# too-wide one (2026-09-01 field-regression-gate investigation - this was
# caught live, not theorized). MIN_SLICE_WIDTH_FRACTION is relative to the
# full bounds' own width, not a fixed pixel count - this project's
# silhouettes span a huge native-scale range (a curio's ~40px diamond to
# the Wanderer's 1355px canvas), so an absolute threshold would be wrong
# at one end or the other.
#
# The returned Rect2's own BOTTOM EDGE is the real scanned max-Y among the
# filtered points, NOT full_bounds' own bottom (2026-09-01, anchor-gap
# fix) - compute()'s full bounds is the padded CANVAS edge for a Sprite2D
# (_texture_bounds() returns the whole texture rectangle regardless of
# transparency), which sits below the actual opaque pixels whenever a
# sprite has any transparent padding at its bottom. Confirmed directly
# against the source asset: wanderer_battle.png has 42px of transparent
# padding below its last opaque row (out of 1161 total height) - a real,
# measured gap, not a rounding artifact. EntityShadow.attach() anchors the
# shadow's Y to this rect's own bottom now instead of full_bounds', so the
# shadow lands at the true rendered boot line rather than 42px-native (=
# silhouette_scale-scaled px in screen space) below it. Callers reading
# this rect's width/centre-x (the ONLY things any current caller reads -
# confirmed via entity_shadow.gd) are unaffected either way.
const MIN_SLICE_WIDTH_FRACTION := 0.05
static func compute_bottom_slice(root: Node2D, slice_fraction: float) -> Rect2:
	var full_bounds: Rect2 = compute(root)
	if full_bounds.size == Vector2.ZERO and full_bounds.position == Vector2.ZERO:
		return full_bounds
	var slice_top_y: float = full_bounds.position.y + full_bounds.size.y * (1.0 - slice_fraction)
	var points := PackedVector2Array()
	for child in root.get_children():
		if child is Node2D:
			_collect_points(child, Transform2D.IDENTITY, slice_fraction, points)
	var min_x := INF
	var max_x := -INF
	var max_y := -INF
	# Small epsilon (2026-09-01) - a point sitting EXACTLY on slice_top_y
	# can land a hair below it after float transform math, which would
	# silently drop the very geometry the slice threshold was drawn against.
	var epsilon := 0.01
	for p in points:
		if p.y >= slice_top_y - epsilon:
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
			max_y = maxf(max_y, p.y)
	if min_x > max_x or (max_x - min_x) < full_bounds.size.x * MIN_SLICE_WIDTH_FRACTION:
		return full_bounds
	return Rect2(Vector2(min_x, slice_top_y), Vector2(max_x - min_x, max_y - slice_top_y))

# Gathers `node`'s own real geometry points, transformed all the way into
# ROOT's local space - `accum` is the accumulated transform from root down
# to node's OWN parent (Transform2D.IDENTITY at the top-level call from
# compute_bottom_slice()). Mirrors _bounds_in_parent_space()'s own
# branch-and-stop shape exactly: a Polygon2D contributes its raw vertices
# and does NOT recurse into its own children (consistent with _bounds_for()
# above, which already treats a Polygon2D as a leaf - e.g. Wardling's own
# "Hooves" Polygon2D children, nested under LeftArm/RightArm/LeftLeg/
# RightLeg, are excluded from compute()'s existing bounds today too; this
# stays consistent with that rather than quietly measuring more geometry
# than the rest of the codebase already does).
static func _collect_points(node: Node2D, accum: Transform2D, slice_fraction: float, out_points: PackedVector2Array) -> void:
	var node_transform: Transform2D = accum * node.transform
	if node is Polygon2D:
		for p in (node as Polygon2D).polygon:
			out_points.append(node_transform * p)
		return
	if node is Sprite2D:
		for p in _sprite_bottom_slice_points(node as Sprite2D, slice_fraction):
			out_points.append(node_transform * p)
		return
	if node is AnimatedSprite2D:
		for p in _animated_sprite_bottom_slice_points(node as AnimatedSprite2D, slice_fraction):
			out_points.append(node_transform * p)
		return
	for child in node.get_children():
		if child is Node2D:
			_collect_points(child, node_transform, slice_fraction, out_points)

# A Sprite2D's own bounds are always the full, axis-aligned texture
# rectangle (see _sprite_bounds() above) regardless of how much of that
# canvas is transparent padding - exactly the case compute_bottom_slice()
# exists to handle (the Wanderer's own 1355x1161 canvas around a much
# narrower figure, sword and cape included in the padding, not just the
# edges - see this pass's own investigation report). Reads the decoded
# image ONCE per call and scans ONLY the bottom slice_fraction of its own
# rows (not the whole image - see _texture_bottom_slice_points() below) for
# opaque pixels, returning their positions in the sprite's own local space
# (pre this sprite's own transform - _collect_points() above applies that).
static func _sprite_bottom_slice_points(sprite: Sprite2D, slice_fraction: float) -> PackedVector2Array:
	if sprite.texture == null:
		return PackedVector2Array()
	return _texture_bottom_slice_points(sprite.texture, sprite.centered, sprite.offset, slice_fraction)

static func _animated_sprite_bottom_slice_points(sprite: AnimatedSprite2D, slice_fraction: float) -> PackedVector2Array:
	if sprite.sprite_frames == null or sprite.animation == "":
		return PackedVector2Array()
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null:
		return PackedVector2Array()
	return _texture_bottom_slice_points(texture, sprite.centered, sprite.offset, slice_fraction)

# Shared by both sprite types above, mirroring _texture_bounds()'s own
# split. get_image() reads back the texture's OWN decoded pixels (not a
# raw file load - see this pass's own investigation report on why that
# distinction matters for export builds) - decompress() is a defensive
# no-op for this project's own lossless-imported art (see wanderer_battle.
# png.import's own compress/mode=0) but keeps this correct if a future
# texture is ever imported VRAM-compressed instead, which get_pixel()
# can't read directly.
const ALPHA_THRESHOLD := 0.1
const COLUMN_STRIDE := 2
# Every 2nd column, not every pixel - halves the read count with no visible
# effect on a footprint measurement this coarse (the shadow itself is a
# soft-edged ellipse, not a precision outline); scanning is already
# restricted to the bottom slice_fraction of ROWS, this trims the other
# axis too.
static func _texture_bottom_slice_points(texture: Texture2D, centered: bool, offset: Vector2, slice_fraction: float) -> PackedVector2Array:
	var image: Image = texture.get_image()
	if image == null:
		return PackedVector2Array()
	if image.is_compressed():
		image.decompress()
	var size: Vector2 = texture.get_size()
	var top_left: Vector2 = (-size / 2.0 if centered else Vector2.ZERO) + offset
	var start_row: int = int(size.y * (1.0 - slice_fraction))
	var points := PackedVector2Array()
	for y in range(start_row, int(size.y)):
		for x in range(0, int(size.x), COLUMN_STRIDE):
			if image.get_pixel(x, y).a > ALPHA_THRESHOLD:
				points.append(top_left + Vector2(x, y))
	return points
