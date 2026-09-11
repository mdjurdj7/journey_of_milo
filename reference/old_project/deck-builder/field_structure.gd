extends Area2D
class_name FieldStructure
# Shared exterior trigger for any enterable structure in the field - a
# small building/kiosk/etc. the player walks into to reach its own
# interior scene, the same Area2D "detection zone, walking in is what
# triggers it" idea field_chest.gd/field_blob.gd already use. This
# script is the reusable HALF of the "enterable structure" pattern (see
# field_interior.gd for the other half, the interior shell) - adding a
# SECOND structure later needs only:
#   (a) a new exterior .tscn with THIS script attached + its own hand-
#       drawn Polygon2D silhouette (see field_pay_house.tscn),
#   (b) a new interior .tscn using field_interior.gd as its root + its
#       own bespoke interactable content (see pay_house_interior.tscn),
#   (c) one new preload + one new match case in field_room.gd's
#       _spawn_structure(),
#   (d) a unique structure_id.
# Nothing else changes - this script, field_interior.gd, and RoomState.
# structure_resolved are all already generic.
#
# Optional (e): if the structure is big enough to sit in the room's own
# walking path, give its interior a second door on the far side that
# advances the run directly (see field_interior.gd's own advance_exit_
# door - the real field_exit.gd pattern, not a bespoke one) so the player
# can walk THROUGH the structure instead of being forced back out the
# front every time - see RoomState.structure_bypass_position below for
# why walking around the outside doesn't work for a door that never stops
# being enterable, and pay_window.gd's own use of that same position for
# where claiming the structure's reward leaves the player.

@export var structure_id: String = ""
# Which entry of RoomState.structure_resolved this structure is tracked
# under - mirrors field_blob.gd's own blob_id. Baked into this
# structure's own .tscn (one value per structure, not per spawn) since a
# room only ever contains one instance of any given structure today.

@export var interior_scene: PackedScene = null
# Which interior scene this door leads to - also baked into the
# structure's own .tscn rather than something field_room.gd hands in at
# spawn time, so a new structure never means teaching field_room.gd a
# second field to set - just the one new match case (c) above.

func _ready() -> void:
	body_entered.connect(_on_body_entered)

# The door stays enterable indefinitely - deliberately NOT gated on
# RoomState.structure_resolved and never disconnected. Resolution state
# is something the INTERIOR shows (see pay_window.gd's own resolved/
# inert treatment), not something that blocks re-entering the exterior
# door - a resolved Pay House should still be walkable-into, it just
# looks different once inside.
func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		# Same "remember where the player was standing" handoff field_
		# chest.gd/field_blob.gd already use before their own transitions -
		# this is what lets field_room.gd put the player back at this exact
		# door (not the room's default spawn) once they leave the interior
		# and SceneTransition.go_to() lands back on field_room.tscn. Nothing
		# inside the interior touches player_position/has_saved_position
		# again (see field_interior.gd), so these values are still exactly
		# what was set here by the time the player actually exits.
		#
		# Unlike a chest/blob though, this door never stops being enterable
		# (see the note above _on_body_entered) - so saving body.global_
		# position AS-IS (the contact point, right on this door's own
		# collision box) would put the player right back on top of a still-
		# live trigger the instant they return, re-entering immediately and
		# looping forever. _safe_return_position() pushes that point clear
		# of the door's own box first.
		RoomState.player_position = _safe_return_position(body)
		# A structure big enough to matter (see the Pay House's own
		# scale - roughly 1.5x player height as of the 2026-08-30 field
		# entity scale re-tune, down from an earlier ~2x when the player
		# was taller) sits in the room's path, not off to one
		# side - since this door never stops being enterable, walking
		# around the OUTSIDE to get past it just re-triggers it again and
		# again (there is no "outside," only more of this same live
		# trigger box). structure_bypass_position is the one place clear
		# of it on the far side, ready for the interior's own optional
		# back door (see field_interior.gd) to send the player there
		# instead - "walk through the structure" via its interior, rather
		# than around it.
		RoomState.structure_bypass_position = _safe_bypass_position()
		RoomState.has_saved_position = true
		SceneTransition.go_to(interior_scene.resource_path)

const RETURN_SAFETY_MARGIN := 40.0

@onready var silhouette: Node2D = $Silhouette

# Clear of THIS DOOR's own small CollisionShape2D - not the whole visual
# silhouette (see _safe_bypass_position() below for that, different,
# wider clearance). Reads the shape's real size and this node's own scale
# rather than a fixed number, so a future structure sized differently
# (see the "adding a second structure" recipe above) still gets a
# correct, non-overlapping point for free.
func _door_half_width() -> float:
	var collision := $CollisionShape2D as CollisionShape2D
	var half_width := RETURN_SAFETY_MARGIN
	if collision.shape is RectangleShape2D:
		half_width += (collision.shape as RectangleShape2D).size.x / 2.0 * scale.x
	return half_width

# On whichever side the player approached from, close to the doorway
# itself - "step back outside near where you actually walked in," not
# "clear the whole building" (a wide facade, see field_pay_house.tscn's
# own widened Body/Roof, is mostly just wall - the door is still one
# specific spot on it, and that's what this door's own front exit should
# return next to).
func _safe_return_position(body: Node2D) -> Vector2:
	var collision := $CollisionShape2D as CollisionShape2D
	var door_center_x := collision.global_position.x
	var side := signf(body.global_position.x - door_center_x)
	if side == 0.0:
		side = 1.0
	return Vector2(door_center_x + side * _door_half_width(), body.global_position.y)

# Local-space (this node's own, pre-scale) left/right edges of whatever
# the structure actually draws - not assumed symmetric around x=0, since
# a decorative accent (see field_pay_house.tscn's RustStreak) could in
# principle sit further out on one side than the other.
func _visual_bounds_local() -> Rect2:
	return VisualBounds.compute(silhouette)

# Always the RIGHT side, regardless of approach, and clears the FULL
# visual silhouette (not just the doorway) - unlike _safe_return_
# position() above, this point exists specifically to get the player PAST
# a wide building, toward the room's exit, so it has to clear the whole
# facade, not just the door in it.
func _safe_bypass_position() -> Vector2:
	var bounds := _visual_bounds_local()
	var right_edge_local_x: float = bounds.position.x + bounds.size.x
	var right_edge_world_x: float = global_position.x + right_edge_local_x * scale.x
	return Vector2(right_edge_world_x + RETURN_SAFETY_MARGIN, RoomState.floor_line_y)
