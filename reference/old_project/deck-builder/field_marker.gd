extends Area2D
# EVENT still has no real content (see DESIGN.md's open questions) -
# walking into it just prints what would happen here. SHOP is real:
# walking into it opens the shop window (see field_room.gd's wiring of
# shop_entered below). Instanced by field_room.gd's _spawn_marker().

signal shop_entered()
# Reports the event, same "just announce it, let something else decide
# what it means" shape as Card.card_clicked/LootRow.row_clicked - this
# marker doesn't know a ShopWindow exists; field_room.gd connects the
# two. Doesn't disconnect after firing (unlike a blob, which is consumed
# on defeat) - the marker itself is never used up, so walking in again
# re-fires this and reopens the shop showing whatever stock is still
# left (see RoomState.shop_stock).

var marker_room_type: RoomType.Kind = RoomType.Kind.EVENT
# Set by field_room.gd right after instantiating, before add_child() -
# same "configure fully, then add to tree" ordering as field_blob.gd's
# blob_id, since _ready() reads this too.

const EVENT_COLOR := Color(0.55, 0.25, 0.8, 1)
const SHOP_COLOR := Color(0.25, 0.45, 0.85, 1)

@export var shadow_y_offset: float = 0.0
# Overrides RoomState.entity_shadow_y_offset's own -18 default (2026-08-30,
# shadow-tuning pass) - this marker's square is a plain hand-built
# Polygon2D baked directly into field_marker.tscn, centred exactly on
# this node's own origin (-35..35 both axes) - no trailing cloth/limb,
# nothing for VisualBounds to overestimate. Confirmed live: the shadow
# already lands exactly at half its own height (35px) below this node's
# origin, matching the polygon's own bottom edge exactly - the -18 global
# default would lift it 18px above its real, already-correct base.

@onready var polygon: Polygon2D = $Polygon2D

func _ready() -> void:
	polygon.color = EVENT_COLOR if marker_room_type == RoomType.Kind.EVENT else SHOP_COLOR
	# Contact shadow (2026-08-30, grounding-cue pass) - see entity_shadow.
	# gd's own doc. Marker has no separate visual container - Polygon2D is
	# a direct child of this root, and this root is CENTRE-anchored on
	# its own polygon (-35..35 both axes), so measure_root == self here,
	# not a child node.
	EntityShadow.attach(self, self, shadow_y_offset)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	if marker_room_type == RoomType.Kind.EVENT:
		print("An event would happen here")
	else:
		shop_entered.emit()
