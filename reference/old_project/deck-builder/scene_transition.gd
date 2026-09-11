extends CanvasLayer
# Another autoload (see run_state.gd for the fuller explanation of what
# that means and why it's different from class_name). This one owns
# moving between scenes instead of run state. Any script that wants to
# change scenes calls SceneTransition.go_to("res://some_scene.tscn")
# instead of calling Godot's change_scene_to_file() directly, so every
# scene change in the game gets the same fade, and there's exactly one
# place this logic lives - not copy-pasted into every scene that needs to
# move to another one. This is where a future map -> battle -> reward ->
# map loop will hook in too, unchanged.
#
# It's a CanvasLayer (not a plain Node) with a `layer` higher than any
# scene's own UI layer (see title_screen.tscn / battle.tscn, both layer
# 1 by default) so its black fade rectangle always draws on top of
# whatever scene is currently active, no matter which one that is.

const FADE_DURATION := 0.3

const FIELD_ROOM_SCENE_PATH := "res://field_room.tscn"
# The one scene_path go_to() ever receives that means "another field
# room" (room_state.gd's load_room(), field_interior.gd, reward_screen.gd,
# and battle.gd's own field-return branch all pass this exact literal) -
# see go_to()'s own ambient-bed note below for what this gates.

@onready var fade_rect: ColorRect = $FadeRect

# Fix (2026-08-24): a transition's own fade-in tween (see go_to() below)
# used to be pausable like anything else, defaulting to PROCESS_MODE_
# PAUSABLE. If whatever scene just loaded paused the tree BEFORE that
# fade-in tween finished, the tween froze mid-flight and go_to()'s own
# coroutine never reached its last line (fade_rect.mouse_filter = IGNORE)
# - leaving fade_rect, a full-screen ColorRect on a CanvasLayer already
# layered above every scene's own UI on purpose (see this file's own
# header), sitting there with mouse_filter = STOP forever, silently
# eating every hover/click in the game with nothing left able to unpause
# the tree to release it. Reported as "I cannot interact with or hover
# over the buttons" on reward_screen.gd's weapon pickup window, which
# pauses almost immediately after loading (see its own _open_weapon_
# reward()) - well before this fade-in's 0.3s naturally finishes. This
# scenario never came up before: nothing in the game had ever paused
# that early after a transition. Making the WHOLE transition immune to
# pause, unconditionally, is the correct fix (not a band-aid on the one
# caller that happened to expose it) - a fade transition finishing
# reliably shouldn't depend on what the destination scene does the
# instant it loads.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# Fades to black, swaps the scene, then fades back in. Callers can
# `await` this (like title_screen.gd does) to run code after the new
# scene is showing, or just call it and move on if nothing needs to wait.
func go_to(scene_path: String) -> void:
	# A looping sound (walking - see player.gd/audio_manager.gd) started
	# in whatever scene we're leaving has no reason to know it's about to
	# disappear - stopping it here gives immediate feedback that the
	# transition started, instead of the sound dragging on through the
	# whole fade-out. Same reasoning for background music (see music_
	# manager.gd) - the title theme has no reason to know it's about to
	# be left behind either, and unlike the walking loop there's no
	# per-frame call anywhere that could restart it mid-fade, so one stop
	# here (not the walking loop's second post-swap call too) is enough.
	#
	# EXCEPT the region's own ambient bed, going to ANOTHER field room
	# (2026-08-31 ambient pass) - see BiomeData.ambient_loop_name and
	# AudioManager.stop_all_looping_except()'s own doc. A field-room-to-
	# field-room transition (walking through a door) is the only scene_
	# path this game ever passes that comes right back to field_room.tscn,
	# so it's the only case checked here; every other destination (battle,
	# an interior, a menu) stops the ambient loop exactly like any other
	# loop, same as before this pass. field_room.gd's own _ready() re-
	# starts the bed on arrival regardless (play_looping() no-ops if it's
	# already playing - see that function's own doc) - this exemption only
	# ever matters for skipping the audible stop-then-restart in between.
	var ambient_loop_name := ""
	if scene_path == FIELD_ROOM_SCENE_PATH:
		ambient_loop_name = RunState.current_biome.ambient_loop_name
	if ambient_loop_name != "":
		AudioManager.stop_all_looping_except(ambient_loop_name)
	else:
		AudioManager.stop_all_looping()
	# Same field-room-to-field-room exemption, same reasoning, for the
	# region's own continuous field MUSIC now too (2026-09-03, Region 1
	# field music pass - see BiomeData.field_music_track and field_room.
	# gd's own _start_region_field_music()) - a field-room-to-field-room
	# transition is still the only destination this exempts; battle, an
	# interior, a menu, all still stop whatever's playing exactly as
	# before. field_room.gd's own _ready() re-starts (or, if already
	# playing the exact same track, no-ops on - see MusicManager.play_
	# music()'s own guard) the field music on arrival regardless, so
	# skipping the stop here is what turns an audible stop-then-restart
	# into silent continuation, same as the ambient loop's own exemption
	# just above.
	var field_music_track := ""
	if scene_path == FIELD_ROOM_SCENE_PATH:
		field_music_track = RunState.current_biome.field_music_track
	if field_music_track == "":
		MusicManager.stop_music()

	# Block clicks during the transition so a stray click can't land on
	# whatever's fading out (or the half-loaded new scene).
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	var fade_out := create_tween()
	fade_out.tween_property(fade_rect, "modulate:a", 1.0, FADE_DURATION)
	await fade_out.finished

	get_tree().change_scene_to_file(scene_path)
	# change_scene_to_file() swaps the scene at the end of the current
	# frame, not instantly - waiting one frame here means the new scene
	# has actually finished entering the tree before we fade it in.
	await get_tree().process_frame

	# The outgoing scene was still alive (and its _physics_process still
	# running) for the ENTIRE fade-out above - if the player was still
	# holding a movement key during those 0.3s, player.gd could call
	# play_looping("walking") again after the stop above already ran,
	# restarting the loop. Since AudioManager is an autoload, that
	# restarted loop survives the scene swap with nothing left alive to
	# stop it - the walking sound bleeding into battle. Stopping again
	# here, now that the new scene (with no Player in it, or a fresh one
	# standing still) is actually active, closes that window for good.
	#
	# Same ambient exemption as the pre-fade call above, symmetric on
	# purpose - a field-room-to-field-room transition would otherwise
	# survive the first call only to be killed by this safety-net one a
	# moment later, defeating the whole point.
	if ambient_loop_name != "":
		AudioManager.stop_all_looping_except(ambient_loop_name)
	else:
		AudioManager.stop_all_looping()

	var fade_in := create_tween()
	fade_in.tween_property(fade_rect, "modulate:a", 0.0, FADE_DURATION)
	await fade_in.finished

	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
