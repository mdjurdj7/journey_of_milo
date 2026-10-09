extends RefCounted
class_name InkPen

# The battle UI's tapered pen - the hand the intent glyphs (BattleIntent)
# and the Devour jaw (DevourButton) are drawn in: each stroke a filled
# ribbon, a full pen width at its body narrowing to `taper` of it at its
# fine ends, the whole glyph ink over a bone outline. Static, so each
# caller keeps its own pen weights as exports and passes them in.

# A glyph as filled ink over a bone outline, at alpha: `shapes` are its
# pen strokes and solid parts, already closed polygons. Overlapping ones
# are merged first, so a dimmed glyph doesn't darken where two strokes
# cross; the outline is each merged piece grown by outline_px
# (offset_polygon, round joins), all of it drawn before any ink - the
# filled equivalent of a label's outline. A dimmed glyph skips the edge
# pass (edge_px): a line over a translucent fill shows as a darker rim.
static func draw_ink(canvas: CanvasItem, shapes: Array[PackedVector2Array], ink: Color, outline: Color, outline_px: float, edge_px: float, alpha: float) -> void:
	ink.a *= alpha
	outline.a *= alpha
	var edge: float = edge_px if alpha >= 1.0 else 0.0
	var pieces: Array[PackedVector2Array] = merged(shapes)
	if outline_px > 0.0:
		for piece in pieces:
			fill(canvas, Geometry2D.offset_polygon(piece, outline_px, Geometry2D.JOIN_ROUND), outline, edge)
	for piece in pieces:
		var filled: Array[PackedVector2Array] = [piece]
		fill(canvas, filled, ink, edge)

# A pen stroke as a closed polygon: each spine point pushed out either
# side by half the width there - the pen's full width (stroke_px) at
# factor 1, `taper` of it at 0 - along the bisector of its two segments,
# mitred so a corner keeps its width; out along the left side and back
# along the right.
static func ribbon(spine: PackedVector2Array, factors: PackedFloat32Array, stroke_px: float, taper: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var count: int = spine.size()
	for i in count:
		var into: Vector2 = (spine[i] - spine[i - 1]).normalized() if i > 0 else Vector2.ZERO
		var out: Vector2 = (spine[i + 1] - spine[i]).normalized() if i < count - 1 else Vector2.ZERO
		var tangent: Vector2 = (into + out).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var miter: float = 1.0
		if into != Vector2.ZERO and out != Vector2.ZERO:
			miter = 1.0 / maxf(normal.dot(Vector2(-out.y, out.x)), 0.5)
		var half: float = stroke_px * lerpf(taper, 1.0, factors[i]) * 0.5 * miter
		left.append(spine[i] + normal * half)
		right.append(spine[i] - normal * half)
	right.reverse()
	left.append_array(right)
	return left

# The shapes with every overlapping pair merged, wherever the union is one
# plain polygon (a union that would enclose a hole leaves them apart),
# each wound counter-clockwise - fill()'s mark of an outer edge.
static func merged(shapes: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = []
	pieces.assign(shapes)
	var merging: bool = true
	while merging:
		merging = false
		for i in pieces.size():
			for j in range(i + 1, pieces.size()):
				if Geometry2D.intersect_polygons(pieces[i], pieces[j]).is_empty():
					continue
				var union: Array[PackedVector2Array] = Geometry2D.merge_polygons(pieces[i], pieces[j])
				if union.size() != 1:
					continue
				pieces[i] = union[0]
				pieces.remove_at(j)
				merging = true
				break
			if merging:
				break
	for i in pieces.size():
		if Geometry2D.is_polygon_clockwise(pieces[i]):
			pieces[i].reverse()
	return pieces

# Fills polygons in the Geometry2D convention - outer edges counter-
# clockwise, holes clockwise (an outline offset round a near-closed
# stroke, the shield, encloses one) - each hole cut into the outer that
# holds it so the fill is one simple polygon. Then, with edge > 0, every
# edge traced in an antialiased line that wide.
static func fill(canvas: CanvasItem, polygons: Array[PackedVector2Array], color: Color, edge: float) -> void:
	var outers: Array[PackedVector2Array] = []
	var holes: Array[PackedVector2Array] = []
	for polygon in polygons:
		if polygon.size() < 3:
			continue
		if Geometry2D.is_polygon_clockwise(polygon):
			holes.append(polygon)
		else:
			outers.append(polygon)
	for outer in outers:
		var inside: Array[PackedVector2Array] = []
		for hole in holes:
			if Geometry2D.is_point_in_polygon(hole[0], outer):
				inside.append(hole)
		var filled: PackedVector2Array = keyholed(outer, inside)
		if Geometry2D.triangulate_polygon(filled).is_empty():
			push_warning("InkPen: a glyph shape didn't triangulate - skipped.")
			continue
		canvas.draw_colored_polygon(filled, color)
		if edge > 0.0:
			var loops: Array[PackedVector2Array] = [outer]
			loops.append_array(inside)
			for loop in loops:
				var closed: PackedVector2Array = loop.duplicate()
				closed.append(loop[0])
				canvas.draw_polyline(closed, color, edge, true)

# `outer` with each hole joined in through a zero-width cut between their
# closest pair of points: out along the cut, round the hole, back.
static func keyholed(outer: PackedVector2Array, holes: Array[PackedVector2Array]) -> PackedVector2Array:
	var polygon: PackedVector2Array = outer
	for hole in holes:
		var best_outer: int = 0
		var best_hole: int = 0
		var best: float = INF
		for i in polygon.size():
			for j in hole.size():
				var distance: float = polygon[i].distance_squared_to(hole[j])
				if distance < best:
					best = distance
					best_outer = i
					best_hole = j
		var joined := PackedVector2Array()
		for i in best_outer + 1:
			joined.append(polygon[i])
		for k in hole.size() + 1:
			joined.append(hole[(best_hole + k) % hole.size()])
		for i in range(best_outer, polygon.size()):
			joined.append(polygon[i])
		polygon = joined
	return polygon
