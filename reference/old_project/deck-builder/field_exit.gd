extends Area2D
# Same Area2D detection-zone idea as blobs/chests - walking into a door is
# what triggers it. Doesn't decide what happens next anymore (DESIGN.md's
# field movement redesign: navigation redesign step 3) - it just reports
# that the player committed to leaving via exit_entered, the same "just
# announce it, let something else decide what it means" shape field_
# marker.gd's shop_entered already uses. field_room.gd connects this to
# the map screen's travel-open entry point (see its _spawn_exits()) -
# the map is what actually decides which room comes next and loads it,
# not this door. No target_node anymore either: a room only ever has
# this one door now (step 1), and which graph edge gets taken is a map
# selection, not something baked into the door itself.
#
# Instanced dynamically by field_room.gd's _spawn_exits() - exactly ONE
# per room (step 1), regardless of how many forward edges the graph node
# actually has.
#
# Combat rooms lock every door in the room until every encounter in it is
# defeated (see field_room.gd's _update_exit_lock(), which calls
# lock()/unlock() on each door) - avoidance decisions come later with
# aggro/branching mechanics (see DESIGN.md's Run Structure & Navigation);
# for now a combat room is about fighting, not routing around a fight.

signal exit_entered()

# No visual of its own any more (2026-08-28, exit-haze pass - see field_
# room.gd's own ExitHaze doc) - locked/unlocked used to read as a flat
# colored Polygon2D rectangle (LOCKED_COLOR/UNLOCKED_COLOR, flashing
# white on unlock); that's gone, replaced by a screen-space atmospheric
# haze at the right edge of the viewport that brightens on approach,
# which doesn't need to know or care whether THIS specific door is
# locked. locked itself, and the animate parameter's SHAPE, are
# unchanged - field_room.gd's _update_exit_lock() still calls lock()/
# unlock() exactly as before and still gates _on_body_entered() below on
# the same bool; only the "and also recolor a polygon" half of each is
# gone, since there's no polygon left to recolor.

var locked: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func lock() -> void:
	locked = true

# animate no longer does anything visually (nothing left to flash) - kept
# as a parameter purely so field_room.gd's own two call sites (unlock(),
# unlock(false)) don't need to change; see this file's own header.
func unlock(animate: bool = true) -> void:
	locked = false

func _on_body_entered(body: Node2D) -> void:
	if locked:
		return
	if body is Player:
		AudioManager.play_sfx("door_opened")
		exit_entered.emit()
