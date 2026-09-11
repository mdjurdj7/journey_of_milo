extends Area2D
# Same Area2D "detection zone, walking in is what triggers it" idea
# field_marker.gd/field_chest.gd/field_blob.gd already use. This script
# decides NOTHING about what happens once touched - see npc_entered
# below, the same "just announce it, let something else decide what it
# means" shape field_marker.gd's own shop_entered/event-print split
# already follows, one step further: even the "what does touching her
# actually DO" decision lives outside this script entirely, not just the
# "which window opens" half marker.gd still makes for itself. Instanced
# by field_room.gd's _spawn_npc().

signal npc_entered()
# Reports the touch, nothing more - field_room.gd decides what it means
# (offer her line, or show nothing if RunState.npc_interacted already
# has her - see field_room.gd's own _on_npc_entered()), the same "just
# announce it, let something else decide" split field_marker.gd's own
# shop_entered → shop_window.open_shop wiring already established. This
# script doesn't know whether she's been talked to before, or what
# accepting even does.

signal npc_exited()
# The walk-away counterpart to npc_entered above - lets field_room.gd
# clear whatever contact-tracking state it's keeping (see its own
# _on_npc_in_contact-shaped var) and call hide_offer() below. Without
# this, only ever knowing "she was entered" and never "she was left"
# would leave the offer text stuck showing (and a click still able to
# accept) long after the player walked off.

var npc_data: NPCData = null
# Which NPC this trigger represents - set by field_room.gd right after
# instantiating, before add_child() (same "configure fully, then add to
# tree" ordering as field_blob.gd's blob_id/field_marker.gd's marker_
# room_type, since _ready() below reads this too). Holds her whole
# static identity (name, dialogue, granted card, silhouette - see npc_
# data.gd) - this script never reaches into any of those fields itself
# except visual_scene, to build her silhouette; everything else is
# there for whatever eventually listens to npc_entered to read.

@onready var visual_root: Node2D = $VisualRoot
@onready var offer_label: Label = $OfferLabel
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

@export var shadow_y_offset: float = -10.6
# Overrides RoomState.entity_shadow_y_offset's own -18 default (2026-08-30,
# shadow-tuning pass) - MEASURED, not assumed: her cloak's own ragged hem
# (the visually obvious "trailing cloth") sits well above her boots in
# Keeper.png, not below them, so it was never the deepest point VisualBounds
# actually measures - her boots are. A targeted per-column alpha scan of
# Keeper.png found her boots' real solid-pixel bottom at row ~1457 of 1536
# (the same row a naive whole-image alpha>0.01 scan also lands on - the
# soft glow/vignette visible around her figure doesn't reach far enough to
# change this). Through her transform (Sprite offset=-620, this NPC's own
# visual_scale=0.135): real bottom = (1457.5 - 768 + -620) * 0.135 = 9.38;
# VisualBounds' own (nominal-cell) bottom = (768 + -620) * 0.135 = 19.98.
# The gap is only ~10.6px - SMALLER than the -18 global default, not
# larger. Applying -18 here would overshoot, lifting her shadow visibly
# above her real boot line.


@export_group("Approach")
@export var trigger_width_px: float = 360.0
# How wide her contact zone is (CollisionShape2D's own RectangleShape2D.
# size.x, widened here at _ready() rather than hand-edited in the .tscn
# so it stays a feel-tunable export like everything else on this scene) -
# 2026-08-27, "don't stand on top of her" fix. The ORIGINAL box (70px)
# was narrower than her own rendered silhouette width, so a player
# walking up had to overlap her sprite before npc_entered even fired -
# both figures crammed into the same space the instant anything showed.
# Widened well past her silhouette so contact - and her offer text -
# fires while the player is still a clear distance away. Height
# (size.y, still the .tscn's own 130) is untouched; only the horizontal
# approach distance needed widening; a click-to-approach also has to
# stop short of her now instead of walking to her exact position - see
# field_room.gd's own _on_npc_clicked() and approach_stop_distance_px
# below for that half of this fix.
@export var approach_stop_distance_px: float = 190.0
# How far from her CENTER a click-to-approach (field_room.gd's _on_npc_
# clicked()) stops, on whichever side the player was already standing -
# a SEPARATE knob from trigger_width_px above, not derived from it,
# since "how far away does contact fire" and "where does a click-walk
# stop" are two different feels even though they're related.
#
# CORRECTED (2026-08-27, live-play fix): the overlap check this value
# actually needs to satisfy is the player's own COLLISION EDGE landing
# inside the trigger, not this value alone staying under trigger_width_
# px / 2 - the player's Area2D contact is 50px wide (field_room.tscn's
# RectangleShape2D_player), so the real bound is `approach_stop_
# distance_px < trigger_width_px / 2 + 25` (half the player's own
# width), not `< trigger_width_px / 2` as this comment originally,
# incorrectly, claimed - that earlier version left real headroom
# sitting unused.
#
# Retuned to 190 (was 140) specifically so the gap the player ends up
# standing at after a CLICK approach reads similarly to the gap that's
# already there the instant CONTACT fires on a KEYBOARD approach - the
# two arrival methods otherwise produced visibly different distances
# (140 alone landed the click-arrival gap at ~51px vs keyboard's own
# ~116px at first contact, confirmed headlessly) even though both are
# meant to read as "she stopped a clear, similar distance away." 190
# lands the click gap at ~101px against keyboard's ~116px (within 15px,
# with a 15px overlap-safety margin of its own - see this pass's own
# report for the exact numbers) - close without shaving the overlap
# margin down to nothing.

# --- World-voice offer text (2026-08-27, NPC interaction wire-up) ---
#
# The line she shows on contact - world-voice, not dialogue (see this
# feature's own brief: no quotes, no name label, no speech framing, just
# a line sitting near her the way EnemyData.flavor_text sits near an
# enemy). Spectral, the same serif this project's other world-voice text
# already uses (loot_row.gd's own WEAPON_NAME_FONT, for a weapon pickup's
# name) - full-color/serif for world-voice vs. sans/muted for system-
# voice is this project's own established two-register split (see
# DESIGN.md's Toll section note on the same principle).
const OFFER_FONT: Font = preload("res://assets/fonts/Spectral-Regular.ttf")

@export_group("Offer Text")
@export var offer_font_size: int = 22
# RAISED from 20 (2026-08-28, legibility pass) - a modest bump, not a
# dramatic one, specifically to clear Deck/Map's own 22px (field_room.
# tscn's DeckButton/MapButton theme_override_font_sizes/font_size) rather
# than sit under it. World-voice text reading SMALLER than the system-
# voice UI around it inverts this project's own established register
# hierarchy (world-voice is the primary read, system-voice is secondary -
# see DESIGN.md's Toll section note on the same two-register split) -
# confirmed, not assumed: the OLD 20 genuinely rendered a hair smaller
# than the buttons beside it, not just a feel.
# REDUCED from 23 to 22 (2026-09-01, NPC-scale pass) - alongside NPCData.
# visual_scale dropping to keep her rendered height near the player's own
# (see opening_room_npc.tres), her offer text at 23 started reading as
# oversized next to a now-smaller figure. 22 lands at exact PARITY with
# Deck/Map's own size rather than strictly above it - the 2026-08-28
# rationale above (world-voice shouldn't read smaller than system-voice)
# still holds at parity; it doesn't require reading strictly larger, just
# not smaller. Not reduced further than this - anything below 22 would
# reopen the exact bug that pass fixed.
# No local offer_color export any more (2026-08-30, world-voice color
# fix) - reads HudPalette.WORLD_TEXT directly at the point of use (see
# _ready() below), the same direct-read convention HudPalette.SYSTEM_
# TEXT's own consumers already follow, so this joins the other three
# field prompts (field_heap.gd/field_curio.gd/field_chest.gd) on one
# shared world-voice color instead of four independently-drifting
# copies. Outline is no longer this file's own independent copy either
# (REPLACES the old offer_outline_width/offer_outline_color/offer_
# outline_opacity exports) - now routed through OverlayStyle.apply_to_
# label() like the other three prompts, with use_light_outline=true
# (see _ready() below): WORLD_TEXT is dark, so it needs OverlayStyle's
# light outline preset, the same "dark base text needs a light outline"
# rule HudPalette.SYSTEM_TEXT's own consumers already established.
# Asymmetric on purpose, same instinct as enemy.gd's own flavor_fade_in_
# sec/flavor_fade_out_sec (see its own note): appearing should feel
# immediate (the player just discovered something), fading away should
# feel like it's settling back into the scene, not being snatched off
# because the player's feet drifted. Exported per this feature's own
# brief, not hardcoded.
@export var offer_fade_in_sec: float = 0.2
@export var offer_fade_out_sec: float = 1.1

var _offer_tween: Tween

# Builds her silhouette from npc_data.visual_scene the same way field_
# blob.gd builds an EnemyData's own visual_scene into visual_container -
# a plain instantiate-and-add, plus npc_data.visual_scale applied to
# visual_root itself (2026-08-27, Keeper art pass) - the per-NPC scale
# correction EnemyData.field_visual_scale already established for the
# same reason (every silhouette/sprite is authored at its own arbitrary
# coordinate scale). Applied to the CONTAINER, not the instantiated
# visual node directly, so it composes cleanly regardless of what's
# inside (a Sprite2D today, still a hand-drawn Polygon2D tree for any
# future NPC that wants one) without either needing to know the other
# exists. Null visual_scene (no art authored yet) is left silently
# unhandled, same permissive stance EnemyData.visual_scene's own null
# case gets everywhere else - an NPC with no art yet just shows nothing,
# not a crash.
func _ready() -> void:
	if npc_data.visual_scene != null:
		visual_root.add_child(npc_data.visual_scene.instantiate())
	visual_root.scale = Vector2(npc_data.visual_scale, npc_data.visual_scale)
	# Contact shadow (2026-08-30, grounding-cue pass) - see entity_shadow.
	# gd's own doc. After visual_root's own scale above, not before, so
	# the measured bounds reflect her real rendered size.
	EntityShadow.attach(self, visual_root, shadow_y_offset)
	# Duplicated before mutating - the .tscn's own RectangleShape2D
	# resource would otherwise be a single shared instance every FieldNPC
	# copy points at, the same "duplicate a shared resource before
	# touching it per-instance" rule this project follows for shared
	# StyleBoxFlat/theme resources elsewhere (see card.gd's own _own_
	# zone_styles()).
	var shape: RectangleShape2D = collision_shape.shape.duplicate()
	shape.size.x = trigger_width_px
	collision_shape.shape = shape
	offer_label.add_theme_font_override("font", OFFER_FONT)
	offer_label.add_theme_font_size_override("font_size", offer_font_size)
	offer_label.add_theme_color_override("font_color", HudPalette.WORLD_TEXT)
	# Routed through OverlayStyle.apply_to_label() now (2026-08-30,
	# world-voice color fix - REPLACES the old direct outline theme
	# overrides) - matches field_heap.gd/field_curio.gd/field_chest.gd's
	# own prompt labels exactly. use_light_outline=true because WORLD_TEXT
	# is dark, not light - see the export block's own doc above.
	OverlayStyle.apply_to_label(offer_label, true)
	offer_label.modulate.a = 0.0
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		npc_entered.emit()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		npc_exited.emit()

# Called by field_room.gd once it's decided she actually has something to
# offer (RunState.npc_interacted doesn't have her yet - see its own
# _on_npc_entered()). Sets the text fresh every call rather than once in
# _ready(), since NPCData.dialogue_text could in principle change what it
# reports between calls (it can't today, but this makes no assumption
# either way) and because a future second placeholder line for the
# already-accepted case (see field_room.gd's own report on that decision)
# would otherwise have nowhere to go.
func show_offer(text: String) -> void:
	offer_label.text = text
	_fade_offer_to(1.0, offer_fade_in_sec)

func hide_offer() -> void:
	_fade_offer_to(0.0, offer_fade_out_sec)

# Kill-then-create on a dedicated tween, same shape enemy.gd's own
# _fade_flavor_to() already uses for exactly this reason: a fade already
# in flight (say, fading in) getting interrupted by the opposite call
# (the player immediately turning around) has to restart cleanly from
# wherever alpha actually is, not fight a still-running tween headed the
# other way.
func _fade_offer_to(target_alpha: float, duration: float) -> void:
	if _offer_tween:
		_offer_tween.kill()
	_offer_tween = create_tween()
	_offer_tween.tween_property(offer_label, "modulate:a", target_alpha, duration)
