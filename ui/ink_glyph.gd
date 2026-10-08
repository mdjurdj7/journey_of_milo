extends RefCounted
class_name InkGlyph

# The field HUD row's small line drawings - one hand for all of them:
# open strokes at one width, no fill, no faint second stroke. Each is
# drawn inside `rect` (the row draws them on the numeral's baseline at
# about its cap height); a halo is the same call again first, wider and in
# the halo colour, so the shapes match exactly.
#
# DECK   two card outlines, the back one peeking out up and to the right
# TOLL   the card's Toll mark: an upward arrow over a base line
# GOLD   a stamped coin: a ring with a smaller ring inside - also the
#        loot screen's coin, so gold is one mark everywhere
# GLASSBONE  a narrow angled shard, outline only

enum Kind { NONE, DECK, TOLL, GOLD, GLASSBONE }

# The coin's inner ring, as a fraction of its outer radius.
const COIN_INNER_RATIO: float = 0.45

static func draw(canvas: CanvasItem, kind: Kind, rect: Rect2, width: float, color: Color) -> void:
	match kind:
		Kind.DECK:
			_draw_deck(canvas, rect, width, color)
		Kind.TOLL:
			_draw_toll(canvas, rect, width, color)
		Kind.GOLD:
			draw_coin(canvas, rect.get_center(), minf(rect.size.x, rect.size.y) * 0.5, width, color)
		Kind.GLASSBONE:
			_draw_shard(canvas, rect, width, color)

# The coin by its centre and outer radius - the form the loot screen
# calls directly.
static func draw_coin(canvas: CanvasItem, centre: Vector2, radius: float, width: float, color: Color) -> void:
	canvas.draw_arc(centre, radius, 0.0, TAU, 48, color, width, true)
	canvas.draw_arc(centre, radius * COIN_INNER_RATIO, 0.0, TAU, 32, color, width, true)

# The front card in the lower left; of the back card only what shows past
# it - its left edge above the front card's top, its top, its right edge,
# its bottom back to the front card's right edge.
static func _draw_deck(canvas: CanvasItem, rect: Rect2, width: float, color: Color) -> void:
	var offset: float = rect.size.x * 0.22
	var card := Vector2(rect.size.x * 0.62, rect.size.y - offset)
	var front := Rect2(rect.position + Vector2(0.0, offset), card)
	var back := Rect2(front.position + Vector2(offset, -offset), card)
	canvas.draw_polyline(PackedVector2Array([
		front.position, Vector2(front.end.x, front.position.y), front.end,
		Vector2(front.position.x, front.end.y), front.position,
	]), color, width, true)
	canvas.draw_polyline(PackedVector2Array([
		Vector2(back.position.x, front.position.y), back.position, Vector2(back.end.x, back.position.y),
		back.end, Vector2(front.end.x, back.end.y),
	]), color, width, true)

# CardView's TOLL keyline glyph at row scale.
static func _draw_toll(canvas: CanvasItem, rect: Rect2, width: float, color: Color) -> void:
	var centre: Vector2 = rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) * 0.5
	canvas.draw_line(centre + Vector2(-r * 0.8, r * 0.9), centre + Vector2(r * 0.8, r * 0.9), color, width, true)
	canvas.draw_line(centre + Vector2(0.0, r * 0.6), centre + Vector2(0.0, -r * 0.9), color, width, true)
	canvas.draw_polyline(PackedVector2Array([
		centre + Vector2(-r * 0.55, -r * 0.35), centre + Vector2(0.0, -r * 0.9), centre + Vector2(r * 0.55, -r * 0.35),
	]), color, width, true)

# A narrow kite leaning right, widest a third of the way down from its
# point - a sliver, no facets.
static func _draw_shard(canvas: CanvasItem, rect: Rect2, width: float, color: Color) -> void:
	var centre: Vector2 = rect.get_center()
	var r: float = minf(rect.size.x, rect.size.y) * 0.5
	var tip := centre + Vector2(r * 0.42, -r)
	var foot := centre + Vector2(-r * 0.42, r)
	var along: Vector2 = (tip - foot).normalized()
	var across := Vector2(-along.y, along.x) * r * 0.2
	var widest: Vector2 = tip.lerp(foot, 0.35)
	canvas.draw_polyline(PackedVector2Array([tip, widest + across, foot, widest - across, tip]), color, width, true)
